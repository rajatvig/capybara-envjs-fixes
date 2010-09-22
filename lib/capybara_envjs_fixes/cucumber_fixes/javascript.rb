require 'johnson/tracemonkey'

module Johnson
  module TraceMonkey
    class Runtime
      def compile_with_fixes(script, filename=nil, linenum=nil, global=nil)
        if (filename =~ /env.js$/)
          # when setTimeout is used before submitting a link, the $event array could have been cleared (as env.js is reloaded) before the event is triggerred
          script.gsub!("if ( target.uuid && $events[target.uuid][event.type] ) {", "if ( target.uuid && $events[target.uuid] && $events[target.uuid][event.type] ) {")
          # also __addEventListener__ and __removeEventListener__ may not have defined $events[target.uuid] yet
          script.gsub!("if ( !$events[target.uuid][type] ){", "if ( !$events[target.uuid] ) { $events[target.uuid] = {} }; if ( !$events[target.uuid][type] ){")
          # Typo
          script.gsub!("WARNIING", "WARNING")
          # The Env.js wait_until(secs) method will wait until the eventLoop is quiet for the specified number of seconds
          # This is usefull when waiting for XHR requests to return a result. However there are some jquery libraries that depend
          # upon "eternal" loops. The following method is used to not execute these loops (note that an alternative would be to
          # slow down the loops, or to alter the event_loop.js#wait method to ignore these eternal loops.)
          loopy_functions = ["loopy", "self\.setSizes\(\)", "self\.checkExpand\(\)", "update_next_targets"] # jquery.url_utils.js#loopy, dhtmlxgrid.js#auto-resize, jquery.autogrow.js, application specific
          script.gsub!("return $master.eventLoop.setTimeout($inner,fn,time);",
                       "if ((''+fn).match(/#{loopy_functions.join("|")}/)) { return 9999; } return $master.eventLoop.setTimeout($inner,fn,time);")
          # functions that execute with a specified interval are loopy by definition, so change the behaviour and only execute them once
          script.gsub!("return $master.eventLoop.setInterval($inner,fn,time);", "return $master.eventLoop.setTimeout($inner,fn,time);")
          # skip hrefs defined as "javascript:void(0);"
          script.gsub!('if (url[0] === "#") {', 'if (url[0] === "#" || url === "javascript:void(0);") {');
        end
        if (filename =~ /static.js$/)
          # the table/row.cells() method should return td as well as th's
          script.gsub!("var nl = this.getElementsByTagName(\"td\");", "var nl = this.getElementsByTagName(\"td\"); if (nl.length === 0) { nl = this.getElementsByTagName(\"th\"); }")
          # while cloning select options, the code tries to find the parent of the option, before the option is added to the document
          script.gsub!("var i, anythingSelected;", "if (parent) { var i, anythingSelected;")
          script.gsub!("parent.value = parent.options[0].value;", "parent.value = parent.options[0].value; }")
          # make sure the first select option is selected by default
          script.gsub!("get selectedIndex(){", "get selectedIndex() { var options = this.options; for(var i=0;i<options.length;i++){ if(options[i].selected){ return i; } } if (options.length > 0) { options[0].selected = true; return 0; } return -1;")
        end
        compile_without_fixes(script, filename, linenum, global)
      end
      alias_method_chain :compile, :fixes
    end
  end
end

module CucumberJavascript
  MOCK_DEBUG = %{
    console = {
      log: function (text) {
        Ruby.Rails.logger().debug('*** Javascript: ' + text + ' ***');
      }
    };
  }
  
  # When the timers disable buttons/links just after they have been clicked, the following will not work
  MOCK_SET_TIMEOUT = %{
    setTimeout = function() {
      arguments[0].call();
    };
  }

  MOCK_JQUERY_FADE = %{
    (function() {
      $.fn.fadeOut = function() {
        if($.isFunction(arguments[0])) {
          arguments[0].call();
        } else if($.isFunction(arguments[1])) {
          arguments[1].call();
        }
        return this;
      };
      $.fn.fadeIn = function() {
        if($.isFunction(arguments[0])) {
          arguments[0].call();
        } else if($.isFunction(arguments[1])) {
          arguments[1].call();
        }
        return this;
      };
    })();
  }

  MOCK_ENVJS = %{
    /* fixes the .value property on textareas in env.js */
    var extension = {
      get value() { return this.innerText; },
      set value(newValue) { this.innerText = newValue; }
    };
    var valueGetter = extension.__lookupGetter__('value');
    HTMLTextAreaElement.prototype.__defineGetter__('value', valueGetter);
    var valueSetter = extension.__lookupSetter__('value');
    HTMLTextAreaElement.prototype.__defineSetter__('value', valueSetter);
  }
  MOCK_JAVASCRIPT = (MOCK_DEBUG + MOCK_ENVJS).gsub(/\n/, ' ').freeze # MOCK_SET_TIMEOUT
  MOCK_JQUERY = (MOCK_JQUERY_FADE).gsub(/\n/, ' ').freeze
end

# Before('@javascript') do
Before do
  @__custom_javascript = []
  Capybara.current_session.driver.rack_mock_session.after_request do
    new_body = Capybara.current_session.driver.response.body
    new_body.gsub!("<head>",
                   "<head><script type='text/javascript'>#{CucumberJavascript::MOCK_JAVASCRIPT}</script>");
    new_body.sub!("</html>",
                  %{<script type='text/javascript'>
                    #{CucumberJavascript::MOCK_JQUERY}
                    #{@__custom_javascript.join}
                    </script>
                    </html>})
    new_body.gsub!(%r{<script src="http://[^"]+" type="text/javascript"></script>}, '')
    Capybara.current_session.driver.response.instance_variable_set('@body', new_body)
  end
end
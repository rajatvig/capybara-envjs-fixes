require 'johnson/tracemonkey'

module Johnson
  module TraceMonkey
    class Runtime
      def compile_with_fixes(script, filename=nil, linenum=nil, global=nil)
        if (filename =~ /env.js$/)
          # when setTimeout is used before submitting a link, the $event array could have been cleared (as env.js is reloaded) before the event is triggerred
          script.gsub!("if ( target.uuid && $events[target.uuid][event.type] ) {", "if ( target.uuid && $events[target.uuid] && $events[target.uuid][event.type] ) {")
          script.gsub!("WARNIING", "WARNING")
        end
        if (filename =~ /static.js$/)
          # the table/row.cells() method should return td as well as th's
          script.gsub!("var nl = this.getElementsByTagName(\"td\");", "var nl = this.getElementsByTagName(\"td\"); if (nl.length === 0) { nl = this.getElementsByTagName(\"th\"); }")
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

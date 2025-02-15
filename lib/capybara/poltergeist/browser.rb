require "capybara/poltergeist/errors"
require 'multi_json'
require 'time'

module Capybara::Poltergeist
  class Browser
    ERROR_MAPPINGS = {
      "Poltergeist.JavascriptError" => JavascriptError,
      "Poltergeist.FrameNotFound"   => FrameNotFound,
      "Poltergeist.InvalidSelector" => InvalidSelector
    }

    attr_reader :server, :client, :logger

    def initialize(server, client, logger = nil)
      @server = server
      @client = client
      @logger = logger
    end

    def restart
      server.restart
      client.restart

      self.debug = @debug if @debug
    end

    def visit(url)
      command 'visit', url
    end

    def current_url
      command 'current_url'
    end

    def status_code
      command 'status_code'
    end

    def body
      command 'body'
    end

    def source
      command 'source'
    end

    def title
      command 'title'
    end

    def find(method, selector)
      result = command('find', method, selector)
      result['ids'].map { |id| [result['page_id'], id] }
    end

    def find_within(page_id, id, method, selector)
      command 'find_within', page_id, id, method, selector
    end

    def all_text(page_id, id)
      command 'all_text', page_id, id
    end

    def visible_text(page_id, id)
      command 'visible_text', page_id, id
    end

    def attribute(page_id, id, name)
      command 'attribute', page_id, id, name.to_s
    end

    def value(page_id, id)
      command 'value', page_id, id
    end

    def set(page_id, id, value)
      command 'set', page_id, id, value
    end

    def select_file(page_id, id, value)
      command 'select_file', page_id, id, value
    end

    def tag_name(page_id, id)
      command('tag_name', page_id, id).downcase
    end

    def visible?(page_id, id)
      command 'visible', page_id, id
    end

    def disabled?(page_id, id)
      command 'disabled', page_id, id
    end

    def click_coordinates(x, y)
      command 'click_coordinates', x, y
    end

    def evaluate(script)
      command 'evaluate', script
    end

    def execute(script)
      command 'execute', script
    end

    def within_frame(handle, &block)
      if handle.is_a?(Capybara::Node::Base)
        command 'push_frame', handle[:name] || handle[:id]
      else
        command 'push_frame', handle
      end

      yield
    ensure
      command 'pop_frame'
    end

    def window_handles
      command 'pages'
    end

    def within_window(name, &block)
      command 'push_window', name
      yield
    ensure
      command 'pop_window'
    end

    def click(page_id, id)
      command 'click', page_id, id
    end

    def double_click(page_id, id)
      command 'double_click', page_id, id
    end

    def hover(page_id, id)
      command 'hover', page_id, id
    end

    def drag(page_id, id, other_id)
      command 'drag', page_id, id, other_id
    end

    def drag_by(page_id, id, dimensions)
      left, right = dimensions.fetch(:left, 0), dimensions.fetch(:right, 0)
      up, down = dimensions.fetch(:up, 0), dimensions.fetch(:down, 0)

      x_delta = right - left
      y_delta = down - up

      command 'drag_by', page_id, id, x_delta, y_delta
    end

    def select(page_id, id, value)
      command 'select', page_id, id, value
    end

    def trigger(page_id, id, event)
      command 'trigger', page_id, id, event.to_s
    end

    def reset
      command 'reset'
    end

    def scroll_to(left, top)
      command 'scroll_to', left, top
    end

    def render(path, options = {})
      check_render_options!(options)
      command 'render', path.to_s, !!options[:full], options[:selector]
    end

    def render_base64(format, options = {})
      check_render_options!(options)
      command 'render_base64', format.to_s, !!options[:full], options[:selector]
    end

    def set_paper_size(size)
      command 'set_paper_size', size
    end

    def resize(width, height)
      command 'resize', width, height
    end

    def send_keys(page_id, id, keys)
      command 'send_keys', page_id, id, normalize_keys(keys)
    end

    def network_traffic
      command('network_traffic').values.map do |event|
        NetworkTraffic::Request.new(
          event['request'],
          event['responseParts'].map { |response| NetworkTraffic::Response.new(response) }
        )
      end
    end

    def clear_network_traffic
      command('clear_network_traffic')
    end

    def equals(page_id, id, other_id)
      command('equals', page_id, id, other_id)
    end

    def get_headers
      command 'get_headers'
    end

    def set_headers(headers)
      command 'set_headers', headers
    end

    def add_headers(headers)
      command 'add_headers', headers
    end

    def add_header(header, permanent)
      command 'add_header', header, permanent
    end

    def response_headers
      command 'response_headers'
    end

    def cookies
      Hash[command('cookies').map { |cookie| [cookie['name'], Cookie.new(cookie)] }]
    end

    def set_cookie(cookie)
      if cookie[:expires]
        cookie[:expires] = cookie[:expires].to_i * 1000
      end

      command 'set_cookie', cookie
    end

    def remove_cookie(name)
      command 'remove_cookie', name
    end

    def cookies_enabled=(flag)
      command 'cookies_enabled', !!flag
    end

    def set_http_auth(user, password)
      command 'set_http_auth', user, password
    end

    def js_errors=(val)
      command 'set_js_errors', !!val
    end

    def extensions=(names)
      Array(names).each do |name|
        command 'add_extension', name
      end
    end

    def debug=(val)
      @debug = val
      command 'set_debug', !!val
    end

    def command(name, *args)
      message = { 'name' => name, 'args' => args }
      log message.inspect

      json = JSON.load(server.send(JSON.dump(message)))
      log json.inspect

      if json['error']
        klass = ERROR_MAPPINGS[json['error']['name']] || BrowserError
        raise klass.new(json['error'])
      else
        json['response']
      end
    rescue DeadClient
      restart
      raise
    end

    private

    def log(message)
      logger.puts message if logger
    end

    def check_render_options!(options)
      if !!options[:full] && options.has_key?(:selector)
        warn "Ignoring :selector in #render since :full => true was given at #{caller.first}"
        options.delete(:selector)
      end
    end

    def normalize_keys(keys)
      keys.map do |key|
        case key
        when Array
          # String itself with modifiers like :alt, :shift, etc
          raise Error, 'PhantomJS behaviour for key modifiers is currently ' \
                       'broken, we will add this in later versions'
        when Symbol
          { key: key } # Return a known sequence for PhantomJS
        when String
          key # Plain string, nothing to do
        end
      end
    end
  end
end

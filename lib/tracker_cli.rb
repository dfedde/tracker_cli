require 'rubygems'
require 'bundler/setup'
require 'httparty'
require 'net/http'
require 'uri'
# stop a thread that has failing code in it
Thread.abort_on_exception = true

# this reducer state object is global so maybey its not
# the best but it will work for now
class State
  class << self
    attr_accessor :state
    def reducer(&block)
      @reducer = block
    end

    def subscribe(key, &block)
      @subscriptions ||= {}
      @subscriptions[key] = { block: block }
    end

    def unsubscribe(key)
      @subscriptions ||= {}
      @subscriptions[:thread]&.stop
      @subscriptions.delete key
    end

    # IDEA: this could genarate a diff
    # stack so that you could regress a action
    def reduce(state, action)
      log("\n old state: #{state} \n action: #{action}")
      @state = @reducer[state, action]
      log("\n new_state: #{@state}")

      subscriptions.each do |key, value|
        subscriptions[key][:thread] = Thread.new {value[:block][]}
      end if subscriptions
    end

    def send_action(action)
      reduce state, action
    end

    private

    attr_reader :subscriptions
  end
end

###
# To use a screen the only arugment that the initaliazer expects
# is a block that will create a new window the argumaents passed
# to the block are `[width, height, top, left]`
# example:
# ```
# Screen.new method(:method_that_makes_a_window)
# ```
# ```
# Screen.new { |*args| Curses::Window.new *args )
# ```
class Screen
  attr_accessor :window, :windows, :focused

  def render(&block)
    raise 'you can only render once per screen' if @exists
    @exists = true
    start_key_stream
    @render_thread = Thread.new do
      instance_eval(&block)
      Thread.stop
    end.join
  end

  def finish
    @input_thread.kill
    clean_windows_for self
    @render_thread.run
    @exists = false
  end

  def clean_windows_for(renderer)
    log(@windows.map{|key, value| [ key.class, value.map{|pensil| pensil[:instance].class} ] }.inspect)
    (windows[renderer] || []).map do |win|
      clean_windows_for win[:inst]
      log "cleaning up #{win[:instance]}"
      win[:win].clear
      win[:win].refresh
      win[:win].close
      State.unsubscribe(win[:inst])
      @windows.delete win
      log "cleaned up #{win[:instance]}"
    end
    window.refresh
    windows.delete renderer
  end

  def rerender(component)
    log "rerender #{component.class}"
    clean_windows_for component
    # componet.on_redraw
    component.draw
  end

  def initialize(window)
    @window = window
    @windows = {}
    @focused = self
  end

  def add_component(klass, renderer = self, **opts)
    height = opts[:height] || renderer.lines
    width = opts[:width] || renderer.cols
    top = opts[:top] || renderer.top
    left = opts[:left] || renderer.left

    @windows[renderer] ||= []
    log "adding to #{renderer}"
    log(@windows.map{|key, value| [ key.class, value.map{|pensil| pensil[:instance].class} ] }.inspect)
    log "building #{klass} at  #{[height, width, top, left]}"
    win  = window.subwin(height, width, top, left)
    inst = klass.new(win, self, opts)
    log "built #{inst}"
    inst.on_mount
    State.subscribe(inst) do
      inst.subscribe
    end

    @windows[renderer] << {
      win:      win,
      instance: inst
    }

    inst.draw
    win.refresh
  end

  def lines
    window.maxy
  end

  def cols
    window.maxx
  end

  def top
    window.begy
  end

  def left
    window.begx
  end

  def on_getch
  end

  private

  def start_key_stream
    @input_thread = Thread.new do
      loop do
        ch = window.getch
        focused.on_getch(ch)
      end
    end
  end
end

###
# A pencil is a thing that can draw on a screen
# to alcomponts my be built with admeny otions as you would like
# todo: a pencil should define a event listner that is used when it is infocus
class Pensil
  attr_reader :state

  def on_getch
  end

  ##
  # when the state of a component changes
  # the component redraws
  def state=(state_changes)
    new_state = state.merge state_changes
    @state = new_state
    Thread.new { redraw } # unless new_state == state
  end

  # this happens whenever a pensil is loaded but before it it renderd
  def on_mount
  end

  def get_focus
    screen.focused = self
  end

  def add_component(klass, **opts)
    screen.add_component klass, self, **opts
  end

  def initialize(window, screen, opts)
    @screen = screen
    @window = window
    @opts = opts
    @state = get_inital_state
  end

  def get_inital_state
    {}
  end

  def cols
    window.maxx
  end

  def lines
    log self
    window.maxy
  end

  def top
    window.begy
  end

  def left
    window.begx
  end

  def clear
  end

  # maybe draw is given the window
  def draw
    raise 'do not render Pensil directly'
  end

  protected

  attr_reader :window, :opts

  private

  def redraw
    screen.rerender self
  end

  attr_reader :screen
end

class Tracker
  include HTTParty
  base_uri 'https://www.pivotaltracker.com/services/v5'

  def self.get(path, token, args = {})
    uri = URI("https://www.pivotaltracker.com/#{path}")

    response = ''
    Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      request = Net::HTTP::Get.new uri
      request['X-TrackerToken'] = token
      res = http.request request # Net::HTTPResponse object
      response = JSON.parse(res.body)
    end
    response
  end

  def self.login(email, token)
    @token ||= get_token(email, token)
  end

  def self.get_token(email, password)
    uri = URI('https://www.pivotaltracker.com/services/v5/me')

    token = ''
    Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      request = Net::HTTP::Get.new uri

      uname = email
      password = password
      log "uname:#{uname} password: #{password}"
      request.basic_auth uname, password

      response = http.request request # Net::HTTPResponse object
      log response.body
      token = JSON.parse(response.body)['api_token']
    end
    token
  end
end

class Main < Pensil
  def on_mount
    self.state = { page: State.state[:page] }
    $stderr.puts state
  end

  def subscribe
    log 'ran'
    self.state = { page: State.state[:page] }
    log 'finished running ran'
  end

  def draw
    case state[:page]
    when :login
      add_component(LoginScreen)
    when :project
      add_component(ProjectView)
    else
      raise('state page must be set')
    end
  end
end

class LoginScreen < Pensil
  def on_mount
    get_focus
  end

  def on_getch(char)
    send(state[:input_func], char)
  end

  def login_input(char)
    self.state = case char
                 when 127
                   { user_name: state[:user_name][0..-2] }
                 when 10
                   { input_func: :password_input }
                 else
                   { user_name: state[:user_name] += char }
                 end
  end

  def password_input(char)
    case char
    when 127
      self.state = { password: state[:password][0..-2] }
    when 10
      login
    else
      self.state = { password: state[:password] += char }
    end
  end

  def login
    token = Tracker.login(state[:user_name], state[:password])
    if token
      State.send_action type: :set_token, page: token
      State.send_action type: :set_page, page: :project
    else
      self.state = { input_func: :login_input }
    end
  end

  def get_inital_state
    { user_name: '', password: '', input_func: :login_input }
  end

  def draw
    add_component(Logo,
                  width: 90,
                  top: 0,
                  left: (cols - 90)/2
                 )

    add_component(TextField,
                  height: 3,
                  width: 60,
                  top: (lines)/2,
                  left: (cols - 60)/2,
                  prompt: 'username:',
                  value:  state[:user_name]
                 )

    add_component(PasswordField,
                  height: 3,
                  width: 60,
                  top: (lines + 4)/2,
                  left: (cols - 60)/2,
                  prompt: 'password:',
                  value: state[:password],
                  connected: true
                 )
  end
end

class PasswordField < Pensil
  def draw
    add_component(TextField,
                  **opts,
                  value: ?* * opts[:value].length
                 )
  end
end

class TextField < Pensil
  def draw
    window.setpos(1, 1)
    window.addstr "#{opts[:prompt]} "
    window.addstr opts[:value]

    window.setpos(0, 0)
    if opts[:connected]
      window.addstr("├#{?─*(cols-2)}┤")
    else
      window.addstr("┌#{?─*(cols-2)}┐")
    end
    (lines - 2).times.with_index do |i|
      line = i + 1
      right = left = ?│
      window.setpos(line, 0)
      window.addstr right
      window.setpos(line, cols - 1)
      window.addstr left
    end
    window.setpos(lines, 0)
    window.addstr("└#{?─*(cols-2)}┘")
  end
end

class SplashScreen < Pensil
  def draw
    add_component(Logo,
                  height: opts[:height],
                  width: opts[:width],
                  top: opts[:top],
                  left: opts[:left]
                 )
  end
end

class Logo < Pensil
  def draw
    lines = File.expand_path(File.dirname(__FILE__))
    File.foreach("#{lines}/tracker_logo").with_index do |line, i|
      window.setpos(i, 0)
      window.addstr line
    end
    window.refresh
  end
end

class ProjectView < Pensil
  def on_mount
    get_focus
  end

  def draw
    top_message = State.state[:project]
    window.setpos(0, (cols - top_message.length) / 2)
    window.addstr top_message

    width = (cols / 3)
#, BacklogList, IceboxList
    [CurrentList].map.with_index do |klass, i|
      add_component klass,
                    project: State.state[:project],
                    height: lines - 1,
                    width: width,
                    top: 1,
                    left: i * width
    end
  end
end

class StoryList < Pensil
  def highlight
    @highlight = true
  end

  def dehighlight
    @highlight = false
  end

  def toggle_highlight
    @highlight = !@highlight
  end

  def highlighted?
    @highlight
  end

  def draw
    stories = opts[:stories]
    title = opts[:title]
    window.clear

    # hor_char = (highlighted? && ?+) || ?-
    # vert_char = (highlighted? && ?+) || ?|
    line_count = 1
    window.setpos(line_count, (cols - title.length) / 2)
    line_count += 1
    window.addstr(title)
    barline = line_count

    stories.each do |story|
      window.setpos(line_count += 1, 1)
      log("drawing story(#{story.id})")
      window.addstr(story.name.slice(0, cols - 17).to_s)
      window.setpos(line_count, cols - (story.current_state.length + 3))
      window.addstr(story.current_state.to_s)
    end

    window.setpos(0, 0)
    window.addstr("┌#{?─*(cols-2)}┐")
    (lines - 2).times.with_index do |i|
      line = i + 1
      right = left = ?│
      window.setpos(line, 0)
      if barline == line
        window.addstr("├#{?─*(cols-2)}┤")
      else
        window.addstr right
        window.setpos(line, cols - 1)
        window.addstr left
      end
    end
    window.setpos(lines, 0)
    window.addstr("└#{?─*(cols-2)}┘")
  end
end

class CurrentList < Pensil
  def draw
    add_component(StoryList, stories: stories, title:  'Current')
  end

  def stories
    []
  end

  def project
    State.state[:project]
  end
end

class BacklogList < Pensil
  def draw
    add_component(StoryList, stories: get_stories, title:  'Backlog')
  end

  def get_stories
    $stderr.puts('get stories back')
    PivotalTracker::Iteration.backlog(project).map(&:stories).flatten
  end

  def project
    State.state[:project]
  end
end

class IceboxList < Pensil
  def draw
    add_component(StoryList, stories: get_stories, title:  'Icebox')
  end

  def get_stories
    $stderr.puts('get stories ice')
    @stories = project
               .stories
               .all
               .select { |story| %w(unscheduled).include? story.current_state }
  end

  def project
    State.state[:project]
  end
end

def log msg
  $stderr.puts msg
  $stderr.flush
end


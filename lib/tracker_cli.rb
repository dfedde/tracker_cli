require 'rubygems'
require 'bundler/setup'
require 'pivotal-tracker'
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

    def subscribe(&block)
      @subscriptions ||= []
      @subscriptions << block
    end

    # IDEA: this could genarate a diff
    # stack so that you could regress a action
    def reduce(state, action)
      @state = @reducer[state, action]
      log(@state)
      Thread.new { subscriptions.each(&:call) } if subscriptions
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
    tr = Thread.new do
      loop do
        ch = window.getch
        focused.on_getch(ch)
      end
    end

    instance_eval(&block)

    tr.kill
    clean_windows_for self
  end

  def clean_windows_for(renderer)
    (windows[renderer] || []).map do |win|
      clean_windows_for win[:inst]
      log "cleaning up #{win[:instance].class}"
      win[:win].clear
      win[:win].refresh
      win[:win].close
    end
    window.refresh
    windows[renderer] = []
  end

  def rerender(component)
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
    log "building #{klass} at  #{[height, width, top, left]}"
    win  = window.subwin(height, width, top, left)
    inst = klass.new(win, self, opts)
    inst.on_mount

    @windows[renderer] << {
      win:      win,
      instance: inst
    }

    log "rendering #{klass} at  #{[height, width, top, left]}"
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
end

###
# A pencil is a thing that can draw on a screen
# to alcomponts my be built with admeny otions as you would like
# todo: a pencil shold define a event listner that is used when it is infocus
class Pensil
  attr_reader :state

  def on_getch
  end

  ##
  # when the state of a component changes
  # the component redraws
  def state=(state_changes)
    new_state = state.merge state_changes
    $stderr.puts "changigng #{self.class.name}'s state to #{new_state}"
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
    log inspect
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

class Main < Pensil
  def on_mount
    self.state = { page: State.state[:page] }
    State.subscribe do
      self.state = { page: State.state[:page] }
    end
    $stderr.puts state
  end

  def draw
    $stderr.puts state
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
      token = login(state[:email], state[:password])
      State.send_action type: :set_token, page: token
      State.send_action type: :set_page, page: :project
    else
      self.state = { password: state[:password] += char }
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
    File.foreach("#{File.expand_path(File.dirname(__FILE__))}/tracker_logo").with_index do |line, i|
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
    $stderr.puts 'im in here'
    window.addstr top_message
    window.refresh

    width = (cols / 3)
    [CurrentList, BacklogList, IceboxList].map.with_index do |klass, i|
      add_component klass,
        project: State.state[:project],
        height: lines-1,
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
    add_component(StoryList, stories: get_stories, title:  'Current')
  end

  def get_stories
    $stderr.puts('get stories current')
    project.iteration(:current).stories
    PivotalTracker::Iteration.current(project).stories
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

def get(path, token, args = {})
	uri = URI("https://www.pivotaltracker.com/#{path}")

  response = ''
	Net::HTTP.start(uri.host, uri.port, :use_ssl => true) do |http|
		request = Net::HTTP::Get.new uri
    request['X-TrackerToken'] = token
		res = http.request request # Net::HTTPResponse object
		response = JSON.parse(res.body)
	end
  response
end

def login(email, token)
  @token ||= get_token(email, token)
end

def get_token(email, password)
  uri = URI('https://www.pivotaltracker.com/services/v5/me')

  token = ''
  Net::HTTP.start(uri.host, uri.port, :use_ssl => true ) do |http|
    request = Net::HTTP::Get.new uri

    uname = email
    password = password
    request.basic_auth uname, password

    response = http.request request # Net::HTTPResponse object
    token = JSON.parse(response.body)['api_token']
  end
  token
end

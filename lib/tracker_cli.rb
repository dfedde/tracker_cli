require 'rubygems'
require 'bundler/setup'

require 'pivotal-tracker'

#this reducer state object is global so maybey its not
#the best but it will work for now
class State
  class << self
    attr_accessor :state
    def reducer &block
      @reducer = block
    end

    # IDEA: this could genarate a diff
    # stack so that you could regress a action
    def reduce state, action
      @state = @reducer[state, action]
    end

    def send_action action
      reduce state, action
    end
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
  attr_accessor :window, :windows

  def render &block
    listen = true
    Thread.new do
      while listen
        window.getch
      end
    end

    instance_eval(&block)
    clean_windows_for self
    listen = false
  end

  def clean_windows_for renderer
    windows[renderer].map do |win|
      $stderr.puts "cleaning up #{win[:instance].class}"
      win[:win].clear
      win[:win].refresh
      win[:win].close
    end
    window.refresh
    windows[renderer] = []
  end

  def initialize(window)
    @window = window
    @windows = {}
  end

  def add_component(klass, renderer = self, **opts)
    height, width, top, left = [
      opts[:height] || renderer.lines,
      opts[:width]  || renderer.cols,
      opts[:top]    || renderer.top,
      opts[:left]   || renderer.left
    ]

    @windows[renderer] ||= []
    $stderr.puts "building #{klass} at  #{[height, width, top, left]}"
    win  = window.subwin(height, width, top, left)
    inst = klass.new(win, self, opts)
    inst.on_mount

    @windows[renderer] << {
      win:      win,
      instance: inst
    }

    $stderr.puts "rendering #{klass} at  #{[height, width, top, left]}"
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
end

###
# A pencil is a thing that can draw on a screen
# to alcomponts my be built with admeny otions as you would like 
# todo: a pencil shold define a event listner that is used when it is infocus
class Pensil

  attr_reader :state

  ##
  # when the state of a component changes
  # the component redraws
  def state= state_changes
    new_state = state.merge state_changes
    new_state == state || draw
    @state == new_state
  end

  def on_mount
  end

  def add_component klass, **opts
    screen.add_component klass, self, **opts
  end

  def initialize(window, screen, opts)
    @screen = screen
    @window = window
    @opts = opts
  end

  def cols
    window.maxx
  end

  def lines
    window.maxy
  end

  def top
    window.begy
  end

  def left
    window.begx
  end

  def draw
    raise 'do not render Pensil directly'
  end

  protected

  attr_reader :window, :opts

  private

  attr_reader :screen
end


class LoginScreen < Pensil

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
                  prompt: 'username',
                  value:  'some string'
                 )

    add_component(PasswordField,
                  height: 3,
                  width: 60,
                  top: (lines + 4)/2,
                  left: (cols - 60)/2,
                  prompt: 'password',
                  value: 'password',
                  connected: true
                 )
  end
end

class PasswordField < Pensil

  def draw
    add_component(TextField,
                  **opts,
                  value: ?**opts[:value].length,
                 )
  end

end

class TextField < Pensil

  def draw
    window.setpos(1, 1)
    window.addstr "#{opts[:prompt]}: "
    window.addstr opts[:value]

    window.setpos(0, 0)
    if opts[:connected]
      $stderr.puts 'here'
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

  def draw
    top_message = State.state[:project].name
    window.setpos(0, (cols - top_message.length) / 2)
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
    $stderr.puts("drawing")
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
      $stderr.puts("drawing story(#{story.id})")
      window.addstr("#{story.name.slice(0, cols - 17)}")
      window.setpos(line_count, cols - (story.current_state.length + 3))
      window.addstr("#{story.current_state}")
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
    $stderr.puts("get stories current")
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
    $stderr.puts("get stories back")
    PivotalTracker::Iteration.backlog(project).map{|i| i.stories}.flatten
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
    $stderr.puts("get stories ice")
    @stories = project.stories.all.select{|story| %w(unscheduled).include? story.current_state}
  end

  def project
    State.state[:project]
  end
end

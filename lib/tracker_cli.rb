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
      puts "Im here >>#{state.inspect}<< action >>#{action}<<"
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
  attr_accessor :window_maker

  def initialize(window_maker = false, &block)
    raise ArgumentError.new('provide only a proc or a block') if window_maker && block
    @window_maker = window_maker || block
  end

  def add(klass, width: 0, height: 0, top: 0, left: 0, **opts)
    $stderr.puts "#{klass}  #{[height, width, top, left]}"
    win = window_maker[height, width, top, left]
    klass.new(win, opts).draw()
    win.refresh
  end
end

###
# A pencil is a thing that can draw on a screen
# to alcomponts my be built with admeny otions as you would like 
# todo: a pencil shold define a event listner that is used when it is infocus
class Pensil

  def add_component klass, **opts
    screen.add klass, **opts
  end

  def initialize(window, opts)
    @screen = Screen.new window.method(:subwin)
    @window = window
    @opts = opts
  end

  def cols
    window.maxx
  end

  def lines
    window.maxy
  end

  def draw
    window.addstr("I'm a cat ")
    window.refresh
  end

  protected

  attr_reader :window, :opts

  private

  attr_reader :screen
end

class SplashScreen < Pensil

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
    add_component(StoryList, stories: get_stories, label:  'Current')
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
    add_component(StoryList, stories: get_stories, label:  'Backlog')
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
    add_component(StoryList, stories: get_stories, label:  'Icebox')
  end

  def get_stories
    $stderr.puts("get stories ice")
    @stories = project.stories.all.select{|story| %w(unscheduled).include? story.current_state}
  end

  def project
    State.state[:project]
  end
end

require 'rubygems'
require 'bundler/setup'

require 'pivotal-tracker'

class Pensil

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

  attr_reader :window
end

class ProjectView < Pensil
  def initialize(window)
    @window = window
  end

  def draw(project)
    top_message = project.name
    window.setpos(0, (cols - top_message.length) / 2)
    window.addstr top_message
    window.refresh

    [CurrentList, BacklogList, IceboxList].map.with_index do |klass, i|
      width = (cols / 3)

      win = window.class.new(lines-1, width, 1, i * width)
      pane = klass.new(win, project: project)
      pane.draw
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


  def initialize(window, project:)
    @project = project
    @window = window
  end

  def draw(stories, title)
    $stderr.puts("drawing")
    window.clear

    hor_char = (highlighted? && ?+) || ?-
    vert_char = (highlighted? && ?+) || ?|
    line_count = 1
    window.setpos(line_count, (cols - title.length) / 2)
    line_count += 1
    window.addstr(title)
    window.setpos(line_count, 0)
    line_count += 1
    $stderr.puts("title:#{title} cols:#{cols}")
    window.addstr("#{?-*cols}")

    stories.each do |story|
      window.setpos(line_count += 1, 1)
      $stderr.puts("drawing story(#{story.id})")
      window.addstr("#{story.name.slice(0, cols - 17)}")
      window.setpos(line_count, cols - (story.current_state.length + 3))
      window.addstr("#{story.current_state}")
    end
    window.box(vert_char, hor_char)

    window.refresh
  end

  protected

  attr_reader :project

end

class CurrentList < StoryList

  def draw
   super get_stories, 'Current'
  end

  def get_stories
    $stderr.puts("get stories")
    project.iteration(:current).stories
    PivotalTracker::Iteration.current(project).stories
  end
end

class BacklogList < StoryList

  def draw
   super get_stories, 'BackLog'
  end

  def get_stories
    $stderr.puts("get stories")
    PivotalTracker::Iteration.backlog(project).map{|i| i.stories}.flatten
  end
end

class IceboxList < StoryList

  def draw
   super get_stories, "Icebox"
  end

  def get_stories
    $stderr.puts("get stories")
    @stories = project.stories.all.select{|story| %w(unscheduled).include? story.current_state}
  end
end

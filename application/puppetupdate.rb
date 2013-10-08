class MCollective::Application::Puppetupdate < MCollective::Application
  description "Puppet repository updates Client"
  usage "Usage: mco puppetupdate update_all -T oyldn or mco puppetupdate [update <branch> [<sha1>]]"

  def post_option_parser(configuration)
    if ARGV.length >= 1
      configuration[:command]  = ARGV.shift
      unless configuration[:command] =~ /^update(_all)?$/
        STDERR.puts "Don't understand command '#{configuration[:command]}', please use update <branch> [<sha1>] or update_all"
        exit 1
      end
      configuration[:branch]   = ARGV.shift
      if configuration[:command] == 'update' and configuration[:branch].nil?
        STDERR.puts "Don't understand update without a branch name"
        exit 1
      end
      configuration[:revision] = ARGV.shift || ''
    else
      STDERR.puts "Please specify an action (update <branch>|update_all) on the command line"
      exit 1
    end
  end

  def main
    return unless %w{update_all update}.include? configuration[:command]

    mc = rpcclient("puppetupdate", :options => options)
    printrpc(
      mc.send(configuration[:command],
        :revision => configuration[:revision],
        :branch   => configuration[:branch]))
    mc.disconnect
    printrpcstats
  end
end


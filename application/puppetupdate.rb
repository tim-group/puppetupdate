class MCollective::Application::Puppetupdate < MCollective::Application
  description "Puppet repository updates Client"
  usage "Usage: mco puppetupdate -T oyldn or mco puppetupdate [<branch> [<sha1>]]"

  def post_option_parser(configuration)
    if ARGV.length >= 1
      configuration[:command]  = "update"
      configuration[:branch]   = ARGV.shift
      configuration[:revision] = ARGV.shift
    else
      configuration[:command] = "update_all"
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

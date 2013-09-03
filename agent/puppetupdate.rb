require 'fileutils'

module MCollective
  module Agent
    class Puppetupdate<RPC::Agent
      attr_accessor :dir
      attr_accessor :repo_url

      def initialize
        @debug=true
        @dir=Config.instance.pluginconf['puppetupdate.directory'] || '/etc/puppet'
        @repo_url=Config.instance.pluginconf['puppetupdate.repository'] || 'http://git/git/puppet'
        super
      end

      def git_repo
        Config.instance.pluginconf['puppetupdate.clone_at'] || "#{@dir}/puppet.git"
      end

      action "update" do
        begin
          require 'puppet'
        rescue LoadError => e
          reply.fail! "Cannot load Puppet"
        end

        begin
          update_all_branches()
          update_master_checkout()
          reply[:output] = "Done"
        rescue Exception => e
          reply.fail! "Exception: #{e}"
        end
      end

      action "update_default" do
        validate :revision, String
        validate :revision, :shellsafe

        begin
          require 'puppet'
        rescue LoadError => e
          reply.fail! "Cannot load Puppet"
        end

        begin
          revision = request[:revision]
          update_bare_repo()
          update_branch("default",revision)
          reply[:output] = "Done"
        rescue Exception => e
          reply.fail! "Exception: #{e}"
        end
      end

      def update_master_checkout
        Dir.chdir(@dir) do
          debug "chdir #{@dir} for update_master_checkout"
          exec "git --git-dir=#{git_repo} --work-tree=#{@dir} reset --hard master"
        end
      end

      def update_all_branches(revisions={})
        update_bare_repo()
        branches = branches()
        branches.each {
          |branch|

          debug "WORKING FOR BRANCH #{branch}"
          debug "#{revisions[branch]}"
          if(revisions[branch]==nil)
            update_branch(branch)
          else
            update_branch(branch, revisions[branch])
          end
        }
        write_puppet_conf(branches)
        cleanup_old_branches(branches)
      end

      def cleanup_old_branches(branches)
        local_branches = ["default"]
        branches.each { |branch| local_branches << local_branch_name(branch) }
        all_envs = all_env_branches()
        all_envs.each { |branch|
          if ! local_branches.include?(branch)
            debug "Cleanup old branch named #{branch}"
            exec "rm -rf #{@dir}/environments/#{branch}"
          end
        }
      end

      def write_puppet_conf(branches)
        branches << "default"
        FileUtils.cp "#{@dir}/puppet.conf.base", "#{@dir}/puppet.conf"
        branches.each {
          |branch|
          open("#{@dir}/puppet.conf", "a") {|f|
            f.puts "\n[#{local_branch_name(branch)}]\n"
            f.puts "modulepath=$confdir/environments/#{local_branch_name(branch)}/modules\n"
            f.puts "manifest=$confdir/environments/#{local_branch_name(branch)}/manifests/site.pp\n"
          }
        }
      end

      def branches()
        branches=[]
        Dir.chdir(git_repo) do
          %x[git branch -a].each_line do |line|
            line.strip!
            if line !~ /\//
              branches<<line
            end
          end
        end
        return branches
      end

      def all_env_branches()
        branches=[]
        Dir.chdir("#{@dir}/environments") do
          %x[ls -1].each_line do |line|
            line.strip!
            branches<<line
          end
        end
        return branches
      end

      def update_branch(remote_branch_name, revision="#{remote_branch_name(remote_branch_name)}")
        local_branch_name = local_branch_name(remote_branch_name)
        dir="#{@dir}/environments/#{local_branch_name}/"
        Dir.mkdir("#{@dir}/environments") unless File.exist?("#{@dir}/environments")
        if !File.exist?(dir)
          Dir.mkdir(dir)
        end

        Dir.chdir(dir) do
          debug "chdir #{dir}\ngit reset --hard #{revision} --git-dir=#{git_repo} --work-tree=#{dir}\n"
          exec "git --git-dir=#{git_repo} --work-tree=#{dir} reset --hard #{revision}"
        end
      end

      def remote_branch_name(remote_branch_name)
        if /\* (.+)/.match(remote_branch_name)
          return $1
        end
        return remote_branch_name
      end

      def local_branch_name(remote_branch_name)
        if /(\/|\* )(.+)/.match(remote_branch_name)
          remote_branch_name = $2
        end
        if remote_branch_name == 'master'
          return "masterbranch"
        end
        return remote_branch_name
      end

      def update_bare_repo()
        envDir="#{git_repo}"
        if File.exists?(envDir)
          Dir.chdir(git_repo) do
            debug "chdir #{git_repo}"
            exec("git fetch origin")
            exec("git remote prune origin")
          end
        else
          exec "git clone --mirror #{@repo_url} #{git_repo}"
        end
        debug "done update_bare_repo"
      end

      def debug line
        if true == @debug
          logger.info(line)
        end
      end

      def exec cmd
        debug "Running cmd #{cmd}"
        output=`#{cmd} 2>&1`
        if not $?.success?
          raise "#{cmd} failed with: #{output}"
        end
      end
    end
  end
end


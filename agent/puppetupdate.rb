require 'fileutils'

module MCollective
  module Agent
    class Puppetupdate < RPC::Agent
      attr_accessor :dir, :repo_url

      def initialize
        @debug    = true
        @dir      = config('directory') || '/etc/puppet'
        @repo_url = config('repository') || 'http://git/git/puppet'
        super
      end

      def git_repo
        config('clone_at') || "#{@dir}/puppet.git"
      end

      def load_puppet
        require 'puppet'
      rescue LoadError => e
        reply.fail! "Cannot load Puppet"
      end

      action "update" do
        load_puppet

        begin
          update_all_branches
          update_master_checkout
          reply[:output] = "Done"
        rescue Exception => e
          reply.fail! "Exception: #{e}"
        end
      end

      action "update_default" do
        validate :revision, String
        validate :revision, :shellsafe
        load_puppet

        begin
          revision = request[:revision]
          update_bare_repo
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
        update_bare_repo
        branches = branches
        branches.each do |branch|
          debug "WORKING FOR BRANCH #{branch}"
          debug "#{revisions[branch]}"
          update_branch(branch, revisions[branch])
        end
        write_puppet_conf(branches)
        cleanup_old_branches(branches)
      end

      def cleanup_old_branches(branches)
        local_branches = ["default"]
        branches.each { |branch| local_branches << local_branch_name(branch) }
        all_envs = all_env_branches()
        all_envs.each do |branch|
          next if local_branches.include?(branch)

          debug "Cleanup old branch named #{branch}"
          exec "rm -rf #{@dir}/environments/#{branch}"
        end
      end

      def write_puppet_conf(branches)
        branches << "default"
        FileUtils.cp "#{@dir}/puppet.conf.base", "#{@dir}/puppet.conf"
        branches.each do |branch|
          open("#{@dir}/puppet.conf", "a") do |f|
            f.puts "\n[#{local_branch_name(branch)}]\n"
            f.puts "modulepath=$confdir/environments/#{local_branch_name(branch)}/modules\n"
            f.puts "manifest=$confdir/environments/#{local_branch_name(branch)}/manifests/site.pp\n"
          end
        end
      end

      def branches
        branches=[]
        Dir.chdir(git_repo) do
          %x[git branch -a].each_line do |line|
            line.strip!
            if line !~ /\//
              branches<<line
            end
          end
        end
        branches
      end

      def all_env_branches
        branches=[]
        Dir.chdir("#{@dir}/environments") do
          %x[ls -1].each_line do |line|
            line.strip!
            branches<<line
          end
        end
        branches
      end

      def update_branch(remote_branch_name, revision=nil)
        revision          ||= "#{remote_branch_name(remote_branch_name)}"
        local_branch_name   = local_branch_name(remote_branch_name)
        branch_dir          = "#{@dir}/environments/#{local_branch_name}/"

        Dir.mkdir("#{@dir}/environments") unless File.exist?("#{@dir}/environments")
        Dir.mkdir(branch_dir) unless File.exist?(branch_dir)

        Dir.chdir(branch_dir) do
          debug "git --git-dir=#{git_repo} --work-tree=#{branch_dir} reset --hard #{revision}\n"
          exec "git --git-dir=#{git_repo} --work-tree=#{branch_dir} reset --hard #{revision}"
        end
      end

      def remote_branch_name(remote_branch_name)
        /\* (.+)/.match(remote_branch_name) ? $1 : remote_branch_name
      end

      def local_branch_name(remote_branch_name)
        if /(\/|\* )(.+)/.match(remote_branch_name)
          remote_branch_name = $2
        end

        remote_branch_name == 'master' ? "masterbranch" : remote_branch_name
      end

      def update_bare_repo
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

      def debug(line)
        logger.info(line) if @debug == true
      end

      def exec(cmd)
        debug "Running cmd #{cmd}"
        output=`#{cmd} 2>&1`
        raise "#{cmd} failed with: #{output}" unless $?.success?
      end

    private

      def config(key)
        Config.instance.pluginconf["puppetupdate.#{key}"]
      end
    end
  end
end


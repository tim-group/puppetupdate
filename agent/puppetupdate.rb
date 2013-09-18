require 'fileutils'

module MCollective
  module Agent
    class Puppetupdate < RPC::Agent
      action "update" do
        load_puppet

        begin
          update_all_branches
          git_reset "master"
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

      attr_accessor :dir, :repo_url

      def initialize
        @debug    = true
        @dir      = config('directory') || '/etc/puppet'
        @repo_url = config('repository') || 'http://git/git/puppet'
        super
      end

      def git_dir; @git_dir ||= config('clone_at') || "#{@dir}/puppet.git"; end
      def env_dir; @env_dir ||= "#{@dir}/environments"; end

      def load_puppet
        require 'puppet'
      rescue LoadError => e
        reply.fail! "Cannot load Puppet"
      end

      def git_branches
        @git_branches ||= %x[cd #{git_dir} && git branch -a].
          lines.reject{|l| l =~ /\//}.map(&:strip)
      end

      def env_branches
        @env_branches ||= %x[ls -1 #{env_dir}].lines.map(&:strip)
      end

      def update_all_branches(revisions={})
        update_bare_repo
        git_branches.each do |branch|
          debug "WORKING FOR BRANCH #{branch}"
          debug "#{revisions[branch]}"
          update_branch(branch, revisions[branch])
        end
        write_puppet_conf
        cleanup_old_branches
      end

      def cleanup_old_branches
        local_branches = ["default", *git_branches.map{|b| local_branch_name(b)}]
        env_branches.each do |branch|
          next if local_branches.include?(branch)
          exec "rm -rf #{env_dir}/#{branch}"
        end
      end

      def write_puppet_conf
        File.open("#{@dir}/puppet.conf", "w") do |f|
          f.puts File.read("#{@dir}/puppet.conf.base")

          git_branches.each do |branch|
            local = local_branch_name(branch)
            f.puts "[#{local}]"
            f.puts "modulepath=$confdir/environments/#{local}/modules"
            f.puts "manifest=$confdir/environments/#{local}/manifests/site.pp"
          end
        end
      end

      def update_branch(branch, revision=nil)
        revision          ||= "#{remote_branch_name(branch)}"
        local_branch_name   = local_branch_name(branch)
        branch_dir          = "#{env_dir}/#{local_branch_name}/"

        Dir.mkdir(env_dir) unless File.exist?(env_dir)
        Dir.mkdir(branch_dir) unless File.exist?(branch_dir)

        git_reset revision, branch_dir
      end

      def git_reset(revision, work_tree=@dir)
        exec "git --git-dir=#{git_dir} --work-tree=#{work_tree} reset --hard #{revision}"
      end

      def remote_branch_name(branch)
        /\* (.+)/.match(branch) ? $1 : branch
      end

      def local_branch_name(branch)
        if /(\/|\* )(.+)/.match(branch)
          branch = $2
        end

        branch == 'master' ? "masterbranch" : branch
      end

      def update_bare_repo
        clone_bare_repo and return unless File.exists?(git_dir)
        exec "(cd #{git_dir}; git fetch origin; git remote prune origin)"
      end

      def clone_bare_repo
        exec "git clone --mirror #{@repo_url} #{git_dir}"
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

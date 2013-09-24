require 'fileutils'

module MCollective
  module Agent
    class Puppetupdate < RPC::Agent
      action "update_all" do
        load_puppet

        begin
          update_all_branches
          write_puppet_conf
          cleanup_old_branches request[:cleanup]
          git_reset "master"
          reply[:output] = "Done"
        rescue Exception => e
          reply.fail! "Exception: #{e}"
        end
      end

      action "update" do
        validate :revision, String
        validate :revision, :shellsafe
        validate :branch, String
        validate :branch, :shellsafe
        load_puppet

        begin
          branch   = request[:branch]
          revision = request[:revision]

          update_bare_repo
          update_branch(branch, revision)
          write_puppet_conf
          cleanup_old_branches request[:cleanup]
          reply[:output] = "Done"
        rescue Exception => e
          reply.fail! "Exception: #{e}"
        end
      end

      attr_accessor :dir, :repo_url

      def initialize
        @debug          = true
        @dir            = config('directory') || '/etc/puppet'
        @repo_url       = config('repository') || 'http://git/git/puppet'
        @rewrite_config = config('rewrite_config') || 1
        super
      end

      def git_dir; config('clone_at') || "#{@dir}/puppet.git"; end
      def env_dir; "#{@dir}/environments"; end

      def load_puppet
        require 'puppet'
      rescue LoadError => e
        reply.fail! "Cannot load Puppet"
      end

      def git_branches
        @git_branches ||= %x[cd #{git_dir} && git branch -a].lines.
          reject {|l| l =~ /\//}.
          map {|l| l.gsub(/\*/, '').strip}
      end

      def env_branches
        %x[ls -1 #{env_dir}].lines.map(&:strip)
      end

      def update_all_branches
        update_bare_repo
        git_branches.each {|branch| update_branch(branch) }
      end

      def cleanup_old_branches(config=nil)
        return if config && config !~ /yes|1|true/

        keep = git_branches.map{|b| branch_dir(b)}
        (env_branches - keep).each do |branch|
          exec "rm -rf #{env_dir}/#{branch}"
        end
      end

      def write_puppet_conf
        return unless @rewrite_config && @rewrite_config !~ /yes|1|true/

        File.open("#{@dir}/puppet.conf", "w") do |f|
          f.puts File.read("#{@dir}/puppet.conf.base")

          git_branches.each do |branch|
            local = branch_dir(branch)
            f.puts "[#{local}]"
            f.puts "modulepath=$confdir/environments/#{local}/modules"
            f.puts "manifest=$confdir/environments/#{local}/manifests/site.pp"
          end
        end
      end

      def update_branch(branch, revision=nil)
        branch_path = "#{env_dir}/#{branch_dir(branch)}/"
        Dir.mkdir(env_dir) unless File.exist?(env_dir)
        Dir.mkdir(branch_path) unless File.exist?(branch_path)

        git_reset(revision || branch, branch_path)
      end

      def git_reset(revision, work_tree=@dir)
        exec "git --git-dir=#{git_dir} --work-tree=#{work_tree} reset --hard #{revision}"
      end

      def branch_dir(branch)
        %w{master user agent main}.include?(branch) ? "#{branch}branch" : branch
      end

      def update_bare_repo
        if File.exists?(git_dir)
          exec "(cd #{git_dir}; git fetch origin; git remote prune origin)"
        else
          exec "git clone --mirror #{@repo_url} #{git_dir}"
        end
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
      rescue
        nil
      end
    end
  end
end

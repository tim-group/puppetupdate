require 'fileutils'

module MCollective
  module Agent
    class Puppetupdate < RPC::Agent
      action "update_all" do
        load_puppet

        begin
          update_all_branches
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
          update_single_branch(request[:branch], request[:revision])
          reply[:output] = "Done"
        rescue Exception => e
          reply.fail! "Exception: #{e}"
        end
      end

      attr_accessor :dir, :repo_url, :ignore_branches, :run_after_checkout

      def initialize
        @dir                = config('directory', '/etc/puppet')
        @repo_url           = config('repository', 'http://git/git/puppet')
        @ignore_branches    = config('ignore_branches', '').split ','
        @run_after_checkout = config('run_after_checkout', nil)
        super
      end

      def git_dir; config('clone_at', "#{@dir}/puppet.git"); end
      def env_dir; "#{@dir}/environments"; end

      def load_puppet
        require 'puppet'
      rescue LoadError => e
        reply.fail! "Cannot load Puppet"
      end

      def update_single_branch(branch, revision='')
        load_puppet
        update_branch(branch, revision)
        write_puppet_conf
        cleanup_old_branches
       end

      def strip_ignored_branches(branch_list)
        branch_list.reject { |branch| ignore_branches.include? branch }
      end

      def git_branches
        strip_ignored_branches %x[cd #{git_dir} && git branch -a].lines.
          map {|l| l.gsub(/\*/, '').strip}
      end

      def env_branches
        strip_ignored_branches %x[ls -1 #{env_dir}].lines.map(&:strip)
      end

      def update_all_branches
        update_bare_repo
        git_branches.each {|branch| update_branch(branch) }
        write_puppet_conf
        cleanup_old_branches
      end

      def cleanup_old_branches(config=nil)
        return if config && config !~ /yes|1|true/

        keep = git_branches.map{|b| branch_dir(b)}
        (env_branches - keep).each do |branch|
          run "rm -rf #{env_dir}/#{branch}"
        end
      end

      def write_puppet_conf
        return unless config('rewrite_config', true)
        return if config('rewrite_config', true) =~ /^(0|no|false)$/

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

      def update_branch(branch, revision='')
        update_bare_repo
        return unless git_branches.include? branch

        branch_path = "#{env_dir}/#{branch_dir(branch)}/"
        Dir.mkdir(env_dir) unless File.exist?(env_dir)
        Dir.mkdir(branch_path) unless File.exist?(branch_path)

        git_reset(revision.length > 0 ? revision : branch, branch_path)
        if run_after_checkout
          Dir.chdir(branch_path) { system run_after_checkout }
        end
      end

      def git_reset(revision, work_tree)
        run "git --git-dir=#{git_dir} --work-tree=#{work_tree} reset --hard #{revision}"
        run "git --git-dir=#{git_dir} --work-tree=#{work_tree} clean -dxf"
      end

      def branch_dir(branch)
        branch = branch.gsub /\//, '__'
        branch = branch.gsub /-/, '_'
        %w{master user agent main}.include?(branch) ? "#{branch}branch" : branch
      end

      def update_bare_repo
        git_auth do
          if File.exists?(git_dir)
            run "(cd #{git_dir}; git fetch origin; git remote prune origin)"
          else
            run "git clone --mirror #{@repo_url} #{git_dir}"
          end
        end
      end

      def git_auth
        if ssh_key = config('ssh_key')
          Dir.mktmpdir do |dir|
            wrapper_file = "#{dir}/ssh_wrapper.sh"
            File.open(wrapper_file, 'w') do |f|
              f.print "#!/bin/sh\n"
              f.print "exec /usr/bin/ssh -o StrictHostKeyChecking=no -i #{ssh_key} \"$@\"\n"
            end
            File.chmod(0700, wrapper_file)
            ENV['GIT_SSH'] = wrapper_file
            yield
            ENV.delete 'GIT_SSH'
          end
        else
          yield
        end
      end

      def run(cmd)
        output=`#{cmd} 2>&1`
        raise "#{cmd} failed with: #{output}" unless $?.success?
      end

    private

      def config(key, default=nil)
        Config.instance.pluginconf.fetch("puppetupdate.#{key}", default)
      rescue
        default
      end
    end
  end
end

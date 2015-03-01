require 'fileutils'

module MCollective
  module Agent
    class Puppetupdate < RPC::Agent
      action "update_all" do
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

        begin
          ret = update_single_branch(request[:branch], request[:revision])
          if ret
            reply[:status] = "Done"
            [:from, :to].each { |s| reply[s] = ret[s] }
          else
            reply[:status] = "Deleted"
          end
        rescue Exception => e
          reply.fail! "Exception: #{e}"
        end
      end

      action "git_gc" do
        git_gc
      end

      attr_accessor :dir, :repo_url, :ignore_branches, :run_after_checkout, :remove_branches

      def initialize
        @dir                = config('directory', '/etc/puppet')
        @repo_url           = config('repository', 'http://git/puppet')
        @ignore_branches    = config('ignore_branches', '').split(',').map { |i| regexy_string(i) }
        @remove_branches    = config('remove_branches', '').split(',').map { |r| regexy_string(r) }
        @run_after_checkout = config('run_after_checkout', nil)
        super
      end

      def git_dir
        config('clone_at', "#{@dir}/puppet.git")
      end

      def env_dir
        "#{@dir}/environments"
      end

      def update_single_branch(branch, revision = '')
        whilst_locked do
          update_bare_repo
          ret = update_branch(branch, revision)
          cleanup_old_branches
          ret
        end
      end

      def strip_ignored_branches(branch_list)
        branch_list.reject do |branch|
          branch == '(no branch)' ||
            branch =~ /detached from/ ||
            ignore_branches.select { |b| b.match(branch) }.count > 0
        end
      end

      def git_branches
        strip_ignored_branches `cd #{git_dir} && git branch -a`.lines.
          map { |l| l.gsub(/\*/, '').strip }
      end

      def env_branches
        strip_ignored_branches `ls -1 #{env_dir}`.lines.map(&:strip)
      end

      def update_all_branches
        whilst_locked do
          update_bare_repo
          git_branches.reject do |branch|
            remove_branches.select { |b| b.match(branch) }.count > 0
          end.each {|branch| update_branch(branch) }
          cleanup_old_branches
        end
      end

      def cleanup_old_branches(config = nil)
        return if config && config !~ /yes|1|true/

        keep = git_branches.reject do |branch|
          remove_branches.select { |b| b.match(branch) }.count > 0
        end.map { |b| branch_dir(b) }
        (env_branches - keep).each do |branch|
          run "rm -rf '#{env_dir}/#{branch}'"
        end
      end

      def update_branch(branch, revision = '')
        return unless git_branches.include? branch

        branch_path = "#{env_dir}/#{branch_dir(branch)}/"
        Dir.mkdir(env_dir) unless File.exist?(env_dir)
        Dir.mkdir(branch_path) unless File.exist?(branch_path)

        ret = git_reset(revision.length > 0 ? revision : branch, branch_path)
        if run_after_checkout
          Dir.chdir(branch_path) { ret[:after_checkout] = system run_after_checkout }
        end
        ret
      end

      def git_reset(revision, work_tree)
        from = File.exist?("#{work_tree}/.git_revision") ? run("cat #{work_tree}/.git_revision").chomp : 'unknown'
        run "git --git-dir=#{git_dir} --work-tree=#{work_tree} checkout --detach --force #{revision}"
        run "git --git-dir=#{git_dir} --work-tree=#{work_tree} clean -dxf"
        to = run "git --git-dir=#{git_dir} --work-tree=#{work_tree} rev-parse HEAD"
        File.open("#{work_tree}/.git_revision", 'w') { |f| f.puts to }
        { :from => from, :to => to }
      end

      def branch_dir(branch)
        branch = branch.gsub /\//, '__'
        branch = branch.gsub /-/, '_'
        %w(master user agent main).include?(branch) ? "#{branch}branch" : branch
      end

      def update_bare_repo
        git_auth do
          if File.exist?(git_dir)
            run "(cd #{git_dir}; git fetch origin; git remote prune origin)"
          else
            run "git clone --mirror #{@repo_url} #{git_dir}"
          end
        end
      end

      def git_gc
        run "git --git-dir=#{git_dir} gc --auto --prune"
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
        output = `#{cmd} 2>&1`
        fail "#{cmd} failed with: #{output}" unless $?.success?
        output
      end

      private

      def config(key, default = nil)
        Config.instance.pluginconf.fetch("puppetupdate.#{key}", default)
      rescue
        default
      end

      def whilst_locked
        ret = nil
        File.open('/tmp/puppetupdate.lock', File::RDWR | File::CREAT, 0644) do |lock|
          lock.flock(File::LOCK_EX)
          ret = yield
        end
        ret
      end

      def regexy_string(string)
        if string.match("^/")
          Regexp.new(string.gsub("\/", ""))
        else
          Regexp.new("^#{string}$")
        end
      end
    end
  end
end

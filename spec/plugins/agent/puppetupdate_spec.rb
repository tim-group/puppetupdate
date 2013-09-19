#! /usr/bin/env ruby -S rspec
require 'singleton'
require 'mcollective'
require 'mcollective/logger'
require 'mcollective/log'
require 'mcollective/config'
require 'mcollective/pluginmanager'
require 'mcollective/agent'
require 'mcollective/rpc'
require 'mcollective/rpc/agent'
require 'mcollective/cache'
require 'mcollective/ddl'
require 'test/unit'
require 'yaml'
require 'tmpdir'
require 'spec_helper'

describe 'files/agent/puppetupdate.rb' do
  before do
    @spec_file_dir = File.dirname __FILE__

    agent_file = "#{File.dirname(__FILE__)}/../../../agent/puppetupdate.rb"
    @agent = MCollective::Test::LocalAgentTest.new(
      "puppetupdate", :agent_file => agent_file).plugin

    @gitrepo = Dir.mktmpdir
    tmp_dir = Dir.mktmpdir
    system <<-SHELL
      ( cd #{@gitrepo}
        git init --bare
        cd #{tmp_dir}
        git clone #{@gitrepo} myrepo 2>&1
        cd myrepo
        echo 'helllo' > file1
        git add file1
        git commit -am "my first commit"
        echo 'hello2' > puppet.conf.base
        git add puppet.conf.base
        git commit -am "add puppet.conf.base file"
        git push origin master 2>&1
        git checkout -b branch1 2>&1
        git push origin branch1 2>&1 ) >/dev/null
    SHELL
  end

  context "without repo" do
    it 'clones bare repo' do
      Dir.mktmpdir do |dir|
        # Checkout
        @agent.dir = dir
        @agent.repo_url="#{@gitrepo}"
        @agent.update_bare_repo()
        # Assert it's there
        File.directory?("#{dir}/puppet.git").should be true

        # Checkout a second time to make sure we update right
        @agent = MCollective::Agent::Puppetupdate.new()
        @agent.dir = dir
        lambda { @agent.update_bare_repo() }.should_not raise_error
      end
    end

    it 'finds branches' do
      Dir.mktmpdir do |dir|
        @agent.dir = dir
        @agent.repo_url="#{@gitrepo}"
        # Checkout
        @agent.update_bare_repo()
        # Assert it's there
        File.directory?("#{dir}/puppet.git").should be true

        branches = @agent.git_branches
        branches.size.should be > 1
      end
    end

    it 'local branch name munging' do
      Dir.mktmpdir do |dir|
        @agent.dir = dir
        @agent.repo_url="#{@gitrepo}"
        @agent.branch_dir('foobar').should be == 'foobar'
        @agent.branch_dir('master').should be == 'masterbranch'
        @agent.branch_dir('user').should be == 'userbranch'
        @agent.branch_dir('agent').should be == 'agentbranch'
        @agent.branch_dir('main').should be == 'mainbranch'
      end
    end
  end

  context "with repo" do
    it 'checks out the HEAD by default' do
      Dir.mktmpdir do |dir|
        `git clone #{@gitrepo} #{dir}/myrepo`
        Dir.chdir("#{dir}/myrepo") do
          @agent.dir = "#{dir}/myrepo"
          @agent.repo_url="#{@gitrepo}"
          @agent.update_all_branches
          @agent.git_reset "master"
          Dir.chdir("#{@agent.dir}/environments/masterbranch") do
            master_rev = `git rev-list master --max-count=1`.chomp
            head_rev = `git rev-parse HEAD`.chomp
            master_rev.should be == head_rev
            master_rev.size.should be == 40
          end
        end
      end
    end

    it 'cleans up old branches' do
      Dir.mktmpdir do |dir|
        `git clone #{@gitrepo} #{dir}/myrepo`
        Dir.chdir("#{dir}/myrepo") do
          @agent.dir = "#{dir}/myrepo"
          @agent.repo_url="#{@gitrepo}"
          `mkdir -p #{@agent.dir}/environments/hahah`
          File.exist?("#{@agent.dir}/environments/hahah").should eql true
          @agent.update_all_branches
          File.exist?("#{@agent.dir}/environments/hahah").should eql false
          File.exist?("#{@agent.dir}/environments/masterbranch").should be == true
        end
      end
    end


    it 'checks out an arbitrary Git hash from a fresh repo' do
      Dir.mktmpdir do |dir|
        `git clone #{@gitrepo} #{dir}/myrepo`
        Dir.chdir("#{dir}/myrepo") do
          @agent.dir = "#{dir}/myrepo"
          @agent.repo_url="#{@gitrepo}"
          previous_rev = `git rev-list master --max-count=1 --skip=1`.chomp

          @agent.update_bare_repo
          @agent.update_branch("master", previous_rev)
          File.exist?("#{@agent.dir}/environments/masterbranch/file1").should be == true
          File.exist?("#{@agent.dir}/environments/masterbranch/puppet.conf.base").should be == false
        end
      end
    end
  end
end

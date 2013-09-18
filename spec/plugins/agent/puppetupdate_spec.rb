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
    @spec_file_dir  = File.dirname __FILE__

    agent_file = File.join([File.dirname(__FILE__), "../../../agent/puppetupdate.rb"])
    @agent = MCollective::Test::LocalAgentTest.new("puppetupdate", :agent_file => agent_file).plugin

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
      @agent.local_branch_name('/foobar').should be == 'foobar'
      @agent.local_branch_name('* foobar').should be == 'foobar'
      @agent.local_branch_name('* notmaster').should be == 'notmaster'
      @agent.local_branch_name('* masterless').should be == 'masterless'
      @agent.local_branch_name('* foomasterbar').should be == 'foomasterbar'
      @agent.local_branch_name('* master').should be == 'masterbranch'
    end
  end

  it 'checks out the HEAD by default' do
    Dir.mktmpdir do |dir|
      `git clone #{@gitrepo} #{dir}/myrepo`
      Dir.chdir("#{dir}/myrepo") do
        @agent = MCollective::Agent::Puppetupdate.new
        @agent.dir = "#{dir}/myrepo"
        @agent.repo_url="#{@gitrepo}"
        @agent.update_all_branches()
        @agent.update_master_checkout()
        Dir.chdir("#{@agent.dir}/environments/masterbranch") do
          master_rev = `git rev-list master --max-count=1`.chomp
          head_rev = `git rev-parse HEAD`.chomp
          master_rev.should be == head_rev
          master_rev.size.should be == 40
        end
      end
    end
  end

  it 'does not cleanup default branch at end' do
    Dir.mktmpdir do |dir|
      `git clone #{@gitrepo} #{dir}/myrepo`
      Dir.chdir("#{dir}/myrepo") do
        @agent = MCollective::Agent::Puppetupdate.new
        @agent.dir = "#{dir}/myrepo"
        @agent.repo_url="#{@gitrepo}"
        previous_rev = `git rev-list master --max-count=1 --skip=1`.chomp
        `mkdir -p #{@agent.dir}/environments/default`
        File.exist?("#{@agent.dir}/environments/default").should eql true
        @agent.update_all_branches({"* master"=>previous_rev})
        File.exist?("#{@agent.dir}/environments/default").should eql true
        File.exist?("#{@agent.dir}/environments/masterbranch/file1").should be == true
        File.exist?("#{@agent.dir}/environments/masterbranch/puppet.conf.base").should be == false
      end
    end
  end


  it 'cleans up old branches' do
    Dir.mktmpdir do |dir|
      `git clone #{@gitrepo} #{dir}/myrepo`
      Dir.chdir("#{dir}/myrepo") do
        @agent = MCollective::Agent::Puppetupdate.new
        @agent.dir = "#{dir}/myrepo"
        @agent.repo_url="#{@gitrepo}"
        previous_rev = `git rev-list master --max-count=1 --skip=1`.chomp
        `mkdir -p #{@agent.dir}/environments/hahah`
        File.exist?("#{@agent.dir}/environments/hahah").should eql true
        @agent.update_all_branches({"* master"=>previous_rev})
        File.exist?("#{@agent.dir}/environments/hahah").should eql false
        File.exist?("#{@agent.dir}/environments/masterbranch/file1").should be == true
        File.exist?("#{@agent.dir}/environments/masterbranch/puppet.conf.base").should be == false
      end
    end
  end


  it 'checks out an arbitrary Git hash from a fresh repo' do
    Dir.mktmpdir do |dir|
      `git clone #{@gitrepo} #{dir}/myrepo`
      Dir.chdir("#{dir}/myrepo") do
        @agent = MCollective::Agent::Puppetupdate.new
        @agent.dir = "#{dir}/myrepo"
        @agent.repo_url="#{@gitrepo}"
        previous_rev = `git rev-list master --max-count=1 --skip=1`.chomp
        @agent.update_all_branches({"* master"=>previous_rev})
        File.exist?("#{@agent.dir}/environments/masterbranch/file1").should be == true
        File.exist?("#{@agent.dir}/environments/masterbranch/puppet.conf.base").should be == false
      end
    end
  end

  def initial_checkout(agent,previous_rev)
    agent.update_all_branches({"* master"=>previous_rev})
  end

  def checkout_again(agent,previous_rev)
    agent.update_all_branches({"* master"=>previous_rev})
  end

  it 'checks out an arbitrary Git hash from an existing repo' do
    Dir.mktmpdir do |dir|
      `git clone #{@gitrepo} #{dir}/myrepo`
      Dir.chdir("#{dir}/myrepo") do
        @agent = MCollective::Agent::Puppetupdate.new
        @agent.dir = "#{dir}/myrepo"
        @agent.repo_url="#{@gitrepo}"
        previous_rev = `git rev-list master --max-count=1 --skip=1`.chomp

        initial_checkout(@agent,previous_rev)
        checkout_again(@agent,previous_rev)
        File.exist?("#{@agent.dir}/environments/masterbranch/file1").should be == true
        File.exist?("#{@agent.dir}/environments/masterbranch/puppet.conf.base").should be == false
      end
    end
  end
end

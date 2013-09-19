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
  before(:all) do
    repo_dir = Dir.mktmpdir
    system <<-SHELL
      ( cd #{repo_dir}
        git init --bare
        cd #{Dir.mktmpdir}
        git clone #{repo_dir} . 2>&1
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

    agent_file = "#{File.dirname(__FILE__)}/../../../agent/puppetupdate.rb"
    @agent = MCollective::Test::LocalAgentTest.new(
      "puppetupdate", :agent_file => agent_file).plugin

    @agent.dir      = Dir.mktmpdir
    @agent.repo_url = repo_dir
  end

  let(:agent) { @agent }

  describe "#branch_dir" do
    it "is not using reserved branch" do
      agent.branch_dir('foobar').should be == 'foobar'
      agent.branch_dir('master').should be == 'masterbranch'
      agent.branch_dir('user').should be   == 'userbranch'
      agent.branch_dir('agent').should be  == 'agentbranch'
      agent.branch_dir('main').should be   == 'mainbranch'
    end
  end

  context "without repo" do
    before(:all) { `rm -rf #{agent.dir}` }

    it 'clones bare repo' do
      agent.update_bare_repo
      File.directory?(agent.git_dir).should be true
      agent.git_branches.size.should be > 1
    end
  end

  context "with repo" do
    before(:all) do
      `rm -rf #{agent.dir}`
      `git clone #{agent.repo_url} #{agent.dir}`
      `git clone --mirror #{agent.repo_url} #{agent.dir}/puppet.git`
      agent.update_all_branches
    end

    it 'checks out the HEAD by default' do
      agent.git_reset "master"
      master_rev = `cd #{agent.env_dir}/masterbranch; git rev-list master --max-count=1`.chomp
      head_rev   = `cd #{agent.env_dir}/masterbranch; git rev-parse HEAD`.chomp
      master_rev.should be == head_rev
      master_rev.size.should be == 40
    end

    it 'cleans up old branches' do
      `mkdir -p #{agent.env_dir}/hahah`
      agent.cleanup_old_branches
      File.exist?("#{agent.env_dir}/hahah").should eql false
      File.exist?("#{agent.env_dir}/masterbranch").should be == true
    end

    it 'checks out an arbitrary Git hash from a fresh repo' do
      previous_rev = `cd #{agent.dir}/puppet.git; git rev-list master --max-count=1 --skip=1`.chomp
      agent.update_branch("master", previous_rev)
      File.exist?("#{agent.env_dir}/masterbranch/file1").should be == true
      File.exist?("#{agent.env_dir}/masterbranch/puppet.conf.base").should be == false
    end
  end
end

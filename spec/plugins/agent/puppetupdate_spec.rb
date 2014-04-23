#! /usr/bin/env ruby -S rspec
$: << '.'
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
require 'agent/puppetupdate'

describe MCollective::Agent::Puppetupdate do
  let(:agent) {
    MCollective::Test::LocalAgentTest.new("puppetupdate",
      :agent_file => "#{File.dirname(__FILE__)}/../../../agent/puppetupdate.rb").
    plugin }

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
        git push origin branch1 2>&1
        git checkout -b must_be_hidden 2>&1
        echo 'hi' > file3
        git add file3
        git commit -am"must_be_hidden";
        git push origin must_be_hidden) >/dev/null
    SHELL

    agent.dir      = Dir.mktmpdir
    agent.repo_url = repo_dir
    agent.ignore_branches = [Regexp.new('^leave_me_alone$')]
    agent.remove_branches = [Regexp.new('^must')]

    clean
    clone_main
    clone_bare
    agent.update_all_branches
  end

  it "#strip_ignored_branches works" do
    agent.strip_ignored_branches(['foo', 'bar', 'leave_me_alone']).should == ['foo', 'bar']
  end

  it "#git_dir should depend on config" do
    agent.expects(:config).returns("hello")
    agent.git_dir.should == "hello"
  end

  it "#branch_dir is not using reserved branch" do
    agent.branch_dir('foobar').should == 'foobar'
    agent.branch_dir('master').should == 'masterbranch'
    agent.branch_dir('user').should   == 'userbranch'
    agent.branch_dir('agent').should  == 'agentbranch'
    agent.branch_dir('main').should   == 'mainbranch'
  end

  describe "#update_bare_repo" do
    before { clean && clone_main }

    it "clones fresh repository" do
      agent.update_bare_repo
      File.directory?(agent.git_dir).should be true
      agent.git_branches.size.should be > 1
    end

    it "fetches repository when present" do
      clone_bare
      agent.update_bare_repo
      File.directory?(agent.git_dir).should be true
      agent.git_branches.size.should be > 1
    end
  end

  it '#cleanup_old_branches removes branches no longer in repo' do
    `mkdir -p #{agent.env_dir}/hahah`
    agent.cleanup_old_branches
    File.exist?("#{agent.env_dir}/hahah").should == false
    File.exist?("#{agent.env_dir}/masterbranch").should == true
  end

  it '#cleanup_old_branches does not remove ignored branches' do
    `mkdir -p #{agent.env_dir}/leave_me_alone`
    agent.cleanup_old_branches
    File.exist?("#{agent.env_dir}/leave_me_alone").should == true
  end

  it '#cleanup_old_branches does cleanup removed branches' do
    File.exist?("#{agent.env_dir}/must_be_hidden").should == false
    `mkdir -p #{agent.env_dir}/must_be_hidden`
    agent.cleanup_old_branches
    File.exist?("#{agent.env_dir}/must_be_hidden").should == false
  end

  it 'checks out an arbitrary Git hash from a fresh repo' do
    previous_rev = `cd #{agent.dir}/puppet.git; git rev-list master --max-count=1 --skip=1`.chomp
    agent.update_branch("master", previous_rev)
    File.exist?("#{agent.env_dir}/masterbranch/file1").should == true
    File.exist?("#{agent.env_dir}/masterbranch/puppet.conf.base").should == false
  end

  describe '#cleanup_old_branches' do
    it 'cleans up by default' do
      agent.expects(:run)
      `mkdir -p #{agent.env_dir}/hahah`
      agent.cleanup_old_branches
    end

    it 'cleans up with yes/1/true' do
      %w{yes 1 true}.each do |value|
        agent.expects(:run)
        `mkdir -p #{agent.env_dir}/hahah`
        agent.cleanup_old_branches(value)
      end
    end

    it 'does not cleanup otherwise' do
      agent.expects(:run).never
      `mkdir -p #{agent.env_dir}/hahah`
      agent.cleanup_old_branches('no')
    end
  end

  describe 'updating deleted branch' do
    it 'does not fail and cleans up branch' do
      new_branch 'testing_del_branch'
      agent.update_bare_repo
      agent.update_branch 'testing_del_branch'
      agent.env_branches.include?('testing_del_branch').should == true

      del_branch 'testing_del_branch'
      agent.update_bare_repo
      agent.env_branches.include?('testing_del_branch').should == true

      agent.update_branch 'testing_del_branch'
      agent.cleanup_old_branches
      agent.env_branches.include?('testing_del_branch').should == false
    end
  end

  describe '#git_auth' do
    it 'sets GIT_SSH env from config' do
      agent.stubs(:config).with('ssh_key').returns('hello')
      agent.git_auth { `echo $GIT_SSH`.should be }
    end

    it 'yields directly when config is empty' do
      agent.git_auth { `echo $GIT_SSH` }.strip.should == ''
    end
  end

  def clean
    `rm -rf #{agent.dir}`
  end

  def clone_main
    `git clone #{agent.repo_url} #{agent.dir}`
  end

  def clone_bare
    `git clone --mirror #{agent.repo_url} #{agent.git_dir}`
  end

  def new_branch(name)
    tmp_dir = Dir.mktmpdir
    system <<-SHELL
      git clone #{agent.repo_url} #{tmp_dir} >/dev/null 2>&1;
      cd #{tmp_dir};
      git checkout -b #{name} >/dev/null 2>&1;
      git push origin #{name} >/dev/null 2>&1
    SHELL
  end

  def del_branch(name)
    tmp_dir = Dir.mktmpdir
    system <<-SHELL
      git clone #{agent.repo_url} #{tmp_dir} >/dev/null 2>&1;
      cd #{tmp_dir};
      git push origin :#{name} >/dev/null 2>&1
    SHELL
  end
end

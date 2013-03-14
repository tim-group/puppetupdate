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
require 'test/unit'

describe 'files/agent/puppetupdate.rb' do

  before do
    @spec_file_dir  = File.dirname __FILE__
    @file_under_test_dir = "#{@spec_file_dir}/../../../files"

    require "#{@file_under_test_dir}/mcollective/agent/puppetupdate"

    MCollective::Config.instance.set_config_defaults("/etc/mcollective/server.cfg")
    MCollective::Config.instance.libdir << @file_under_test_dir

    @gitrepo = Dir.mktmpdir

    Dir.chdir(@gitrepo) do
     `git init --bare`
    end

    Dir.mktmpdir {|dir|
      Dir.chdir(dir) {
        `git clone #{@gitrepo} myrepo`
        Dir.chdir("myrepo") {
          `echo 'helllo' > file1`
          `git add file1`
          `git commit -am "my first commit"`
          `echo 'hello2' > puppet.conf.base`
          `git add puppet.conf.base`
          `git commit -am "add puppet.conf.base file"`
          `git push origin master`
          `git checkout -b branch1`
          `git push origin branch1`
        }
      }
  }

  end

  it 'clones bare repo' do
    Dir.mktmpdir {|dir|
      # Checkout
      a = MCollective::Agent::Puppetupdate.new()
      a.dir = dir
      a.repo_url="#{@gitrepo}"
      a.update_bare_repo()
      # Assert it's there
      File.directory?("#{dir}/puppet.git").should be true

      # Checkout a second time to make sure we update right
      puppetupdater = MCollective::Agent::Puppetupdate.new()
      puppetupdater.dir = dir
      lambda { puppetupdater.update_bare_repo() }.should_not raise_error
    }
  end

  it 'finds branches' do
    Dir.mktmpdir {|dir|
      puppetupdater = MCollective::Agent::Puppetupdate.new()
      puppetupdater.dir = dir
      puppetupdater.repo_url="#{@gitrepo}"
      # Checkout
      puppetupdater.update_bare_repo()
      # Assert it's there
      File.directory?("#{dir}/puppet.git").should be true

      branches = puppetupdater.branches()
      branches.size.should be > 1
    }
  end

  it 'local branch name munging' do
    Dir.mktmpdir {|dir|
      puppetupdater = MCollective::Agent::Puppetupdate.new()
      puppetupdater.dir = dir
      puppetupdater.repo_url="#{@gitrepo}"
      puppetupdater.local_branch_name('/foobar').should be == 'foobar'
      puppetupdater.local_branch_name('* foobar').should be == 'foobar'
      puppetupdater.local_branch_name('* notmaster').should be == 'notmaster'
      puppetupdater.local_branch_name('* masterless').should be == 'masterless'
      puppetupdater.local_branch_name('* foomasterbar').should be == 'foomasterbar'
      puppetupdater.local_branch_name('* master').should be == 'masterbranch'
    }
  end

  it 'checks out the HEAD by default' do
    Dir.mktmpdir {|dir|
     `git clone #{@gitrepo} #{dir}/myrepo`
      Dir.chdir("#{dir}/myrepo") {
        puppetupdater = MCollective::Agent::Puppetupdate.new()
        puppetupdater.dir = "#{dir}/myrepo"
        puppetupdater.repo_url="#{@gitrepo}"
        puppetupdater.update_all_branches()
        puppetupdater.update_master_checkout()
        Dir.chdir("#{puppetupdater.dir}/environments/masterbranch") do
          master_rev = `git rev-list master --max-count=1`.chomp
          head_rev = `git rev-parse HEAD`.chomp
          master_rev.should be == head_rev
          master_rev.size.should be == 40
        end
      }

   }
  end

  it 'does not cleanup default branch at end' do
    Dir.mktmpdir {|dir|
     `git clone #{@gitrepo} #{dir}/myrepo`
      Dir.chdir("#{dir}/myrepo") {
        puppetupdater = MCollective::Agent::Puppetupdate.new()
        puppetupdater.dir = "#{dir}/myrepo"
        puppetupdater.repo_url="#{@gitrepo}"
        previous_rev = `git rev-list master --max-count=1 --skip=1`.chomp
        `mkdir -p #{puppetupdater.dir}/environments/default`
        File.exist?("#{puppetupdater.dir}/environments/default").should eql true
        puppetupdater.update_all_branches({"* master"=>previous_rev})
        File.exist?("#{puppetupdater.dir}/environments/default").should eql true
        Dir.chdir("#{puppetupdater.dir}/environments/masterbranch") do
          head_rev = `git rev-parse HEAD`.chomp
          head_rev.should be == previous_rev
          head_rev.size.should be == 40
        end
      }

   }
  end


  it 'cleans up old branches' do
    Dir.mktmpdir {|dir|
     `git clone #{@gitrepo} #{dir}/myrepo`
      Dir.chdir("#{dir}/myrepo") {
        puppetupdater = MCollective::Agent::Puppetupdate.new()
        puppetupdater.dir = "#{dir}/myrepo"
        puppetupdater.repo_url="#{@gitrepo}"
        previous_rev = `git rev-list master --max-count=1 --skip=1`.chomp
        `mkdir -p #{puppetupdater.dir}/environments/hahah`
        File.exist?("#{puppetupdater.dir}/environments/hahah").should eql true
        puppetupdater.update_all_branches({"* master"=>previous_rev})
        File.exist?("#{puppetupdater.dir}/environments/hahah").should eql false
        Dir.chdir("#{puppetupdater.dir}/environments/masterbranch") do
          head_rev = `git rev-parse HEAD`.chomp
          head_rev.should be == previous_rev
          head_rev.size.should be == 40
        end
      }

   }
  end


  it 'checks out an arbitrary Git hash from a fresh repo' do
    Dir.mktmpdir {|dir|
     `git clone #{@gitrepo} #{dir}/myrepo`
      Dir.chdir("#{dir}/myrepo") {
        puppetupdater = MCollective::Agent::Puppetupdate.new()
        puppetupdater.dir = "#{dir}/myrepo"
        puppetupdater.repo_url="#{@gitrepo}"
        previous_rev = `git rev-list master --max-count=1 --skip=1`.chomp
        puppetupdater.update_all_branches({"* master"=>previous_rev})
        Dir.chdir("#{puppetupdater.dir}/environments/masterbranch") do
          head_rev = `git rev-parse HEAD`.chomp
          head_rev.should be == previous_rev
          head_rev.size.should be == 40
        end
      }

   }
  end

  def initial_checkout(puppetupdater,previous_rev)
    puppetupdater.update_all_branches({"* master"=>previous_rev})
  end

  def checkout_again(puppetupdater,previous_rev)
    puppetupdater.update_all_branches({"* master"=>previous_rev})
  end

  it 'checks out an arbitrary Git hash from an existing repo' do
    Dir.mktmpdir {|dir|
     `git clone #{@gitrepo} #{dir}/myrepo`
      Dir.chdir("#{dir}/myrepo") {
        puppetupdater = MCollective::Agent::Puppetupdate.new()
        puppetupdater.dir = "#{dir}/myrepo"
        puppetupdater.repo_url="#{@gitrepo}"
        previous_rev = `git rev-list master --max-count=1 --skip=1`.chomp

        initial_checkout(puppetupdater,previous_rev)
        checkout_again(puppetupdater,previous_rev)

        Dir.chdir("#{puppetupdater.dir}/environments/masterbranch") do
          head_rev = `git rev-parse HEAD`.chomp
          head_rev.should be == previous_rev
          head_rev.size.should be == 40
        end
      }

   }
  end

end

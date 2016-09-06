require 'rubygems'
require 'rake'

require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec) do |t|
  t.pattern = 'spec/**/*_spec.rb'
end

desc "Run lint (Rubocop)"
task :lint do
  sh "/var/lib/gems/1.9.1/bin/rubocop --require rubocop/formatter/checkstyle_formatter "\
     "--format RuboCop::Formatter::CheckstyleFormatter --out tmp/checkstyle.xml"
end


# rubocop:disable ParameterLists
def package(build_dir, root_dir, files, name, version, depends)
  sh "mkdir -p #{build_dir}/#{root_dir}"
  sh "cp #{files} #{build_dir}/#{root_dir}"
  args = [
      '-s', 'dir',
      '-t', 'deb',
      '--architecture', 'all',
      '-C', "#{build_dir}",
      '--name', "mcollective-puppetupdate-#{name}",
      '--version', "#{version}",
      '--prefix', '/usr/share/mcollective/plugins/mcollective/',
      depends.map { |dep| "-d #{dep} " }.join
  ].join(' ')

  sh "fpm #{args}"
end

desc 'Create a debian package'
task :package => [:clean] do
  sh 'mkdir -p build'
  hash = `git rev-parse --short HEAD`.chomp
  v_part = ENV['BUILD_NUMBER'] || "0.pre.#{hash}"
  version = "0.0.#{v_part}"

  package('build/common', 'agent', 'agent/puppetupdate.ddl', 'common', version, [])
  package('build/agent', 'agent', 'agent/puppetupdate.rb', 'agent', version, [])
  package('build/application', 'application', 'application/puppetupdate.rb', 'application', version, [])
end

desc 'Create and install debian package'
task :install => [:package] do
  sh 'sudo dpkg -i *common*.deb'
  sh 'sudo dpkg -i *agent*.deb'
  sh 'sudo dpkg -i *application*.deb'
  sh 'sudo /etc/init.d/mcollective restart;'
end

desc 'Clean artifacts created by this build'
task :clean do
  sh 'rm -rf build'
  sh 'rm  -f *deb'
end

task :default => %w(spec lint)

# puppetupdate

Git branches => Puppet environments, automated with an mcollective
agent

# Usage

The puppetupdate agent will then pull your puppet code and
checkout __/etc/puppet/environments/xxx__ for each branch that you have,
giving you an environment per branch.

This means that you can develop puppet code independently on a branch,
push, mco puppetupdate and then puppet agent -t --environment xxxx on
clients to test (where the environment maps to a branch name)

## Branch name rewriting.

There are a selection of environment names which are not permitted in
puppet.conf, these are:

  * master
  * user
  * agent
  * main

If you have a branch named like this, then puppetupdate will automatically
append 'branch' to the name, ergo a branch in git named 'master'
will become an environment named 'masterbranch'.

Additionally, there are a selection of characters which whilst being
valid git branch names, are not valid puppet environment names.

Notably, the following characters get translated:

  * \- becomes _

  * / becomes __

# Configuration

The following configuration options are recognised in the mcollective
__server.cfg__, under the namespace __plugin.puppetupdate.xxx__

## rewrite_config

If the agent should rewrite your puppet.conf file on deploying branches.

Unless you have a specific need for a not 1:1 mapping of branches
to environments, then it is recommended to set this to false.

Defaults to true (due to hysterical raisins)

## ssh_key

An ssh key to use when pulling puppet code. Note that this key
must __NOT__ have a passphrase.

## directory

Where you keep your puppet code, defaults to __/etc/puppet__

Environments are _always_ under this directory, as is the
checkout of your puppet code (in a directory named puppet.git)
and if __rewrite_config__ is true, then puppet.conf is
rewritten inside this directory.

## repository

The repository location from which to clone the puppet code.

Defaults to __http://git/puppet__

You almost certainly want to change this!

## ignore_branches

A comma separated list of branches to not bother checking out (but not
remove if found).

Defaults to empty.

Often you want to set this to 'production', so that you can symlink
the default branch to puppet client to whatever your default git branch
is called (unless you name your default git branch 'production')

If any of the entries are bracketed by //, then the value is assumed
to be a regular expression.

For example, the setting:

  production,/^foobar/

will ignore the 'production' branch, and also any branch prefixed with 'foobar'

## remove_branches

A comma separated list of branches to never checkout, and remove if found
checked out.

Value behaves in the same manor as ignore_branches

## run_after_checkout

If set, after checking out / updating a branch then puppetupdate
will chdir into the top level /etc/puppet/environments/xxx
directory your branch has just been checked out into, and run the
command configured here.

Use this to (for example) decrypt secrets committed to your
puppet code using a private key only available on puppet masters.

# Installation

Checkout, then just run:

  mco plugin package .

You'll get a .deb or .rpm of the code for this agent, which you
can install on your puppet masters.

## dynamic environments mode

This is the recommended (but not default) deployment mode.

Set the config option __rewrite_config__ to be false.

Arrange your puppet.conf on your puppetmaster to include the
__$environment__ variable, in the __modulepath__ and __manifest__
settings.

## static environments mode.

Set the config option __rewrite_config__ to be true

Arrange for your normal __puppet.conf__ to be named __/etc/puppet/puppet.conf.base__
on your puppet masters

The puppetupdate agent will then write the __puppet.conf__
file out with an entry for each environment.

# LICENSE

MIT licensed (See LICENSE.txt)

# Contributions

Patches are very welcome!


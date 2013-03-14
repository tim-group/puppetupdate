# puppetupdate

This is the TIM Group puppetupdate mcollective agent

You install this agent on puppet masters, and arrange for your
normal puppet.conf to be /etc/puppet/puppet.conf.base

The puppetupdate agent will then pull your puppet code and
checkout /etc/puppet/environments/xxx for each branch that you have,
and write a puppet.conf file out with an entry for each environment.

This means that you can develop puppet code independently on a branch,
push, mco puppetupdate and then puppet agent -t --environment xxxx on
clients to test.

Neat eh?

This code works, but needs some cleanup to take values from the config
file (e.g. repository location currently hard coded at git@git:puppet).

Patches are very welcome!


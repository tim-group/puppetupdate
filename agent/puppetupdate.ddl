metadata :name        => "Puppet Update",
         :description => "Agent To update git branch checkouts on puppetmasters",
         :author      => "Infrastructure Team",
         :license     => "MIT",
         :version     => "1.0",
         :url         => "http://www.timgroup.com",
         :timeout     => 120

action "update", :description => "Update the branch to a specific revision" do
  display :always

  input :revision,
    :description => "revision",
    :display_as  => "the revision to update the default branch to",
    :optional    => true,
    :type        => :string,
    :prompt      => "Git hash",
    :validation  => ".*",
    :maxlength   => 40

  input :branch,
    :description => "branch",
    :display_as  => "the branch to check out into environments",
    :optional    => true,
    :type        => :string,
    :prompt      => "Git branch",
    :validation  => ".+",
    :maxlength   => 255

  input :cleanup,
    :description => "cleanup old branches",
    :display_as  => "cleanup old branches after updating",
    :optional    => true,
    :type        => :string,
    :prompt      => "Cleanup (yes/no)",
    :validation  => ".+",
    :maxlength   => 3

  output :from,
    :description => "The sha we updated from",
    :display_as  => "From"

  output :to,
    :description => "The sha we updated to",
    :display_as  => "To"

  output :status,
    :description => "The status of the git pull",
    :display_as  => "Pull Status"
end

action "update_all", :description => "Update all branches on the puppetmaster" do
  display :always

  input :cleanup,
    :description => "cleanup old branches",
    :display_as  => "cleanup old branches after updating",
    :optional    => true,
    :type        => :string,
    :prompt      => "Cleanup (yes/no)",
    :validation  => ".+",
    :maxlength   => 3

  output :status,
    :description => "The status of the git pull",
    :display_as  => "Pull Status"
end

action "git_gc", :description => "Trigger git garbage collection" do
  display :failed
end

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
    :validation  => ".+",
    :maxlength   => 40

  input :branch,
    :description => "branch",
    :display_as  => "the branch to check out into environments",
    :optional    => true,
    :type        => :string,
    :prompt      => "Git branch",
    :validation  => ".+"

  output :status,
    :description => "The status of the git pull",
    :display_as  => "Pull Status"
end

action "update_all", :description => "Update all branches on the puppetmaster" do
  display :always

  output :status,
    :description => "The status of the git pull",
    :display_as  => "Pull Status"
end

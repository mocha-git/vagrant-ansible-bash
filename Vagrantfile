VAGRANTFILE_API_VERSION = "2"

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
  private_net = "192.168.56."
  ssh_pub_key = File.expand_path("~/.ssh/id_rsa.pub")
  ssh_priv_key = File.expand_path("~/.ssh/id_rsa")

  config.vm.box_check_update = false

  def provision_ssh(vm, key_path)
    vm.vm.provision "file", source: key_path, destination: "/home/vagrant/id_rsa.pub"
    vm.vm.provision "shell", inline: <<~SHELL
      mkdir -p /home/vagrant/.ssh
      cat /home/vagrant/id_rsa.pub >> /home/vagrant/.ssh/authorized_keys
      chmod 600 /home/vagrant/.ssh/authorized_keys
      chown -R vagrant:vagrant /home/vagrant/.ssh
    SHELL
  end

  # DC01 - Windows Server
  config.vm.define "dc01" do |dc|
    dc.vm.box = "StefanScherer/windows_2019"
    dc.vm.hostname = "dc01"
    dc.vm.network "private_network", ip: private_net + "10"
    dc.vm.communicator = "winrm"
    dc.vm.boot_timeout = 1000
    dc.vm.provider "virtualbox" do |vb|
      vb.memory = 2048
      vb.cpus = 2
    end
    dc.vm.provision "shell", path: "scripts/win-setup.ps1"
  end

  # Web01
  config.vm.define "web01" do |web|
    web.vm.box = "ubuntu/jammy64"
    web.vm.hostname = "web01"
    web.vm.network "private_network", ip: private_net + "11"
    web.vm.boot_timeout = 1000
    web.vm.provider "virtualbox" do |vb|
      vb.memory = 1024
      vb.cpus = 1
    end
    provision_ssh(web, ssh_pub_key)
    web.vm.provision "shell", path: "scripts/provision-node-exporter.sh"
    web.vm.provision "shell", path: "scripts/provision-web.sh"
  end

  # DB01
  config.vm.define "db01" do |db|
    db.vm.box = "ubuntu/jammy64"
    db.vm.hostname = "db01"
    db.vm.network "private_network", ip: private_net + "12"
    db.vm.boot_timeout = 1000
    db.vm.provider "virtualbox" do |vb|
      vb.memory = 1024
      vb.cpus = 1
    end
    provision_ssh(db, ssh_pub_key)
    db.vm.provision "shell", path: "scripts/provision-node-exporter.sh"
  end

  # Jumpbox
  config.vm.define "jumpbox" do |jump|
    jump.vm.box = "ubuntu/jammy64"
    jump.vm.hostname = "jumpbox"
    jump.vm.network "private_network", ip: private_net + "13"
    jump.vm.network "forwarded_port", guest: 9090, host: 9090
    jump.vm.boot_timeout = 1000
    jump.vm.provider "virtualbox" do |vb|
      vb.memory = 1024
      vb.cpus = 1
    end
    jump.vm.provision "file", source: ssh_pub_key, destination: "/home/vagrant/id_rsa.pub"
    jump.vm.provision "file", source: ssh_priv_key, destination: "/home/vagrant/id_rsa"
    jump.vm.provision "shell", path: "scripts/run-provision.sh"
  end
end

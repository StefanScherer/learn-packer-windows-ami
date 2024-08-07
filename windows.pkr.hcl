packer {
  required_plugins {
    amazon = {
      version = ">= 0.0.1"
      source = "github.com/hashicorp/amazon"
    }
  }
}

variable "region" {
  type    = string
  default = "us-east-1"
}

locals { 
  timestamp = regex_replace(timestamp(), "[- TZ:]", "")
  username = "Administrator"
  password = "SuperS3cr3t!!!!"
}

# source blocks are generated from your builders; a source can be referenced in
# build blocks. A build block runs provisioner and post-processors on a
# source.
source "amazon-ebs" "firstrun-windows" {
  ami_name      = "packer-windows-demo-${local.timestamp}"
  communicator  = "winrm"
  instance_type = "t2.micro"
  region        = "${var.region}"
  source_ami_filter {
    filters = {
        name                = "Windows_Server-2022-English-Full-Base-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["amazon"]
  }
  user_data      = <<-EOF
<powershell>
# Set administrator password
net user ${local.username} ${local.password}
wmic useraccount where "name='${local.username}'" set PasswordExpires=FALSE

# First, make sure WinRM can't be connected to
netsh advfirewall firewall set rule name="Windows Remote Management (HTTP-In)" new enable=yes action=block

# Delete any existing WinRM listeners
winrm delete winrm/config/listener?Address=*+Transport=HTTP  2>$Null
winrm delete winrm/config/listener?Address=*+Transport=HTTPS 2>$Null

# Disable group policies which block basic authentication and unencrypted login

Set-ItemProperty -Path HKLM:\\Software\\Policies\\Microsoft\\Windows\\WinRM\\Client -Name AllowBasic -Value 1
Set-ItemProperty -Path HKLM:\\Software\\Policies\\Microsoft\\Windows\\WinRM\\Client -Name AllowUnencryptedTraffic -Value 1
Set-ItemProperty -Path HKLM:\\Software\\Policies\\Microsoft\\Windows\\WinRM\\Service -Name AllowBasic -Value 1
Set-ItemProperty -Path HKLM:\\Software\\Policies\\Microsoft\\Windows\\WinRM\\Service -Name AllowUnencryptedTraffic -Value 1


# Create a new WinRM listener and configure
winrm create winrm/config/listener?Address=*+Transport=HTTP
winrm set winrm/config/winrs '@{MaxMemoryPerShellMB="0"}'
winrm set winrm/config '@{MaxTimeoutms="7200000"}'
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
winrm set winrm/config/service '@{MaxConcurrentOperationsPerUser="12000"}'
winrm set winrm/config/service/auth '@{Basic="true"}'
winrm set winrm/config/client/auth '@{Basic="true"}'

# Configure UAC to allow privilege elevation in remote shells
$Key = 'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\System'
$Setting = 'LocalAccountTokenFilterPolicy'
Set-ItemProperty -Path $Key -Name $Setting -Value 1 -Force

# Configure and restart the WinRM Service; Enable the required firewall exception
Stop-Service -Name WinRM
Set-Service -Name WinRM -StartupType Automatic
netsh advfirewall firewall set rule name="Windows Remote Management (HTTP-In)" new action=allow localip=any remoteip=any
Start-Service -Name WinRM
</powershell>
EOF
  winrm_password = "${local.password}"
  winrm_username = "${local.username}"
}

# a build block invokes sources and runs provisioning steps on them.
build {
  name    = "learn-packer"
  sources = ["source.amazon-ebs.firstrun-windows"]

  provisioner "powershell" {
    environment_vars = ["DEVOPS_LIFE_IMPROVER=PACKER"]
    inline           = ["Write-Host \"HELLO NEW USER; WELCOME TO $Env:DEVOPS_LIFE_IMPROVER\"", "Write-Host \"You need to use backtick escapes when using\"", "Write-Host \"characters such as DOLLAR`$ directly in a command\"", "Write-Host \"or in your own scripts.\""]
  }
  // provisioner "windows-restart" {
  // }
  // provisioner "powershell" {
  //   environment_vars = ["VAR1=A$Dollar", "VAR2=A`Backtick", "VAR3=A'SingleQuote", "VAR4=A\"DoubleQuote"]
  //   script           = "./sample_script.ps1"
  // }

  provisioner "ansible" {
    use_proxy       = false
    extra_arguments = [
      "-e", "ansible_connection=winrm",
      "-e", "ansible_winrm_scheme=https",
      "-e", "ansible_winrm_transport=ntlm",
      "-e", "ansible_port=5985",
      // "-e", "ansible_winrm_scheme=https",
      // "-e", "ansible_port=5986",
      // "-e", "ansible_winrm_server_cert_validation=ignore",
      "-e", "user_username=${local.username}",
      "-e", "user_password=${local.password}",
    ]
    playbook_file = "playbook.yml"
  }
}



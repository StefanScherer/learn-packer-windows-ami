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
  user_data_file = "./bootstrap_win.txt"
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



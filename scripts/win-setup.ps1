Import-Module ServerManager
Install-WindowsFeature -Name AD-Domain-Services, DNS -IncludeManagementTools

$domainName = "root.local"
$SafeModePassword = ConvertTo-SecureString -AsPlainText "P@ssw0rd123" -Force

Install-ADDSForest `
    -DomainName $domainName `
    -SafeModeAdministratorPassword $SafeModePassword `
    -DomainNetbiosName "ROOT" `
    -Force:$true

Restart-Computer -Force

<#
    .NOTES
    ===========================================================================
     Créé par:  Christophe HARIVEL
	 Date: 		16 janvier 2020
     Blog:      www.vrun.fr
     Twitter:   @harivchr
    ===========================================================================
    .DESCRIPTION
        L'objectif de ce script est de générer un rapport sur les dernieres sauvegardes Veeam
		Nous supposons que Veeam est configuré pour mettre à jour les Custom Attributes des VMs en cas de sauvegarde réussie
		Script réalisé avec vSphere 6.5
    ===========================================================================
	.NOTICE
        Penser à modifier les variables dans la rubriques "VARIABLES A MODIFIER"
		Puis lancer ./Get-Veeam-Report.ps1
#>
#Import des modules VMware necessaires
# -----------------------------------------------
if (!(Get-PSSnapin -Name VMware.VimAutomation.Core -erroraction "silentlycontinue"))
{
	Import-Module VMware.VimAutomation.Core	
}

#################### VARIABLES A MODFIER ##################################################

# Liste des vCenter à scanner
$VCENTERS = @()
$VCENTERS = "vcenter1","vcenter2","vcenter3"

# Chemin du répertoire de destination
$path = "D:\Export-Veeam"

# Nom du Custom Attribute à analyser (celui configuré dans Veeam)
$CustomAttributeName = "VEEAM_LAST_SUCCESSFUL_BACKUP"

#Parametres Email modifiables
# -----------------------------------------------
$SMTPServer = "serveur SMTP"
$to = "Mail du destinataire"
$from = "Mail de l'expediteur"

#Nombre de jours d'ancienneté de la dernière sauvegarde réussie; ex: -3 
$JJ = -3

#################### DECLARATION DES FONCTIONS ############################################

# Fonction pour récupérer l'attribut Veeam sur toutes les VMs du vCenter
function Get-VM-Attribute (){
	write-host "Recuperation des attributs personalises en cours" -NoNewLine
	
	# On créé le tableau pour le stocker résultat
	$tableau = @()
	
	# On liste l'ensemble des VMs du vCenter 
	$VMsList = get-vm 
	
	# Pour chaque VM du vCenter
	foreach($vm in $VMsList){
		write-host "." -NoNewLine
		
		# On récupère la valeur de l'attribut personnalisé
		$attribut = ($vm | Get-Annotation -CustomAttribute $CustomAttributeName).Value
		
		# On stocke le nom de la VM et la valeur de l'attribut dans le tableau		
		$Object = new-object PSObject
		$Object | add-member -name "VMName" -membertype Noteproperty -value $vm.Name
		$Object | add-member -name "Attribut" -membertype Noteproperty -value $attribut
		$tableau += $Object
	}
	
	# La fonction retourne le tableau comme résultat
	return $tableau
}

# Fonction pour parser le tableau des attributs fournis en argument
function Parse-Attribute ($var){
	# On créé le tableau pour le stocker résultat
	$tableau = @()
	
	# Pour chaque objet du tableau
	foreach($obj in $var){
		# On créé un tableau pour stocker tous les éléments de l'attribut personnalisé
		$value = @()
		
		# On découpe chaque élement (Nom du Job, date, etc...) et on stocke chaque élement dans le tableau $value
		$value = ($obj.Attribut) -split "," 
		
		# Si le 1er élément n'est pas null, alors on supprime les crochets et le suffixe "Veeam Backup:  Job name: " pour ne garder que le nom du Job
		if($value[0] -ne $null){
			$value[0] = ($value[0]).split('[]') -replace "Veeam Backup:  Job name: ",""
		}
		
		# Si le 2e élément n'est pas null, alors on supprime les crochets et le suffixe "Time: " pour ne garder que la date et l'heure
		if($value[1] -ne $null){
			$value[1] = ($value[1]).split('[]') -replace "Time: ",""
		}
		
		# on stocke ces résultats dans un tableau
		$Object = new-object PSObject
		$Object | add-member -name "VMName" -membertype Noteproperty -value $obj.VMName
		$Object | add-member -name "JobName" -membertype Noteproperty -value $value[0]
		$Object | add-member -name "LastSuccessfulBackup" -membertype Noteproperty -value $value[1]
		$tableau += $Object
	}
	# La fonction retourne le tableau comme résultat
	return $tableau
}

# Fonction permettant d'analyser les attributs et ainsi fournir un rapport des VMs non sauvegardees
function Analyse-Attributs ($var){
	# On créé le tableau pour le stocker résultat
	$tableau = @()
	
	# Pour chaque objet du tableau
	foreach($obj in $var){
		# Si le champs "LastSuccessfulBackup" est null cela signifie que la VM n'est pas sauvegardée du tout
		if($obj.LastSuccessfulBackup -eq $null){
			$Object = new-object PSObject
			$Object | add-member -name "VMName" -membertype Noteproperty -value $obj.VMName
			$Object | add-member -name "Result" -membertype Noteproperty -value "No Backup !"
			$tableau += $Object
		}else{
			# Si le champs "LastSuccessfulBackup" n'est pas null, alors cela signifie qu'il y a deja eu une sauvegarde
			# On teste si cette dernière sauvegarde est plus vieille que $JJ jours
			if((get-date($obj.LastSuccessfulBackup)) -lt (get-date).AddDays($JJ)){
				$res = "Last Backup =>" + $obj.LastSuccessfulBackup
				$Object = new-object PSObject
				$Object | add-member -name "VMName" -membertype Noteproperty -value $obj.VMName
				$Object | add-member -name "Result" -membertype Noteproperty -value $res
				$tableau += $Object
			}
		}
	}
	return $tableau
}

# Fonction permettant de créer des credential cryptés dans un fichier txt
# Attention si vous souhaitez automatiser ce script à l'aide d'un compte de service, il faut générer les crédentials à l'aide de ce compte de service
function MakeCredential {
	param($path)
	$path_to_cred = $path + "\cred.txt"
		
	#Si le fichier contenant les credentials existe on lit les infos depuis celui-ci
	if (Test-Path -path $path_to_cred)
	{
		$login,$passwd = type $path_to_cred
		$passwd = convertto-securestring $passwd
		if ($login -ne ""){
			Write-Host "$step - Compte utilise pour export : $login"
		}else{
			Write-Host "$step - Erreur : Login null"
		}
		$step+=1
	}
	#Sinon on en crée un nouveau en demandant les infos de connexion à l'administrateur
	else
	{
		$cred = Get-Credential
		$cred.UserName > $path_to_cred
		convertfrom-securestring $cred.password >> $path_to_cred
		$login = $cred.UserName
		$passwd = $cred.Password
	}
	$cred =  new-object -typename System.Management.Automation.PSCredential -argumentlist $login,$passwd 
	return $cred
}   


#################### DEBUT DU SCRIPT ########################################################
#On génère un crédential pour le compte de service utilisé pour l'export
$ExportCred = MakeCredential -path $path

$CredUser = $ExportCred.username
$ClearCredPassword = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($($ExportCred.password)))


# On execute le script pour chaque vCenter (donc envoi d'un mail par vCenter)
foreach($VC in $VCENTERS){
	
	# Variable de type tableau pour stocker les résultats
	$Resultat = "Toutes les VMs sont correctement sauvegardees."

	############## CONNEXION AU VCENTER
	write-host "Connexion au vCenter: $VC" -foregroundcolor "green"
	Connect-VIServer -server $VC -User $CredUser -Password $ClearCredPassword
	write-host

	############## COLLECTE DES ATTRIBUTS
	$VMsAttributs = Get-VM-Attribute
	write-host

	############## PARSING DES ATTRIBUTS
	# $VMsAttributsParses = Parse-Attribute($VMsAttributs)
	if($VMsAttributs -ne $null){
		$VMsAttributsParses = Parse-Attribute($VMsAttributs)
	}

	############## ANALYSE ET MISE EN FORME DU RAPPORT
	if($VMsAttributsParses -ne $null){
		echo $VMsAttributsParses | ft
		$res = Analyse-Attributs($VMsAttributsParses)
	}
	if($res -ne $null){
		write-host
		echo $res | ft
		$Resultat = @()
		$Resultat = $res | Out-String
	}

	############## EXPORT DES RESULTATS
	
	#### ENVOI DU MAIL
	write-host "Envoi du mail" -foregroundcolor "green"
	$AttachementFileName = ""
	$body = "vCenter : " + $VC + "`n"  # retour a la ligne grace au 'n
	$body += "`n"  # On saute une ligne grace au 'n
	$body += "Voici la liste des VMs qui ne sont pas sauvegardees correctement avec Veeam : `n" 	# retour a la ligne grace au 'n
	$body += "`n" # On saute une ligne grace au 'n
	$Subject = 'Rapport de sauvegarde Veeam pour le vCenter ' + $VC
	$body += $Resultat + "`n" 	# retour a la ligne grace au 'n
	Send-MailMessage -to $to -from $From -Body $body -smtpserver $SMTPServer -Subject $Subject
	
	#### EXPORTS DU FICHIER CSV
	# Nom du fichier final
	$CSVfilename = "Veeam_Report_" + $VC + "_" + (Get-Date -Format "yyyy-MM-dd") + ".csv"
	write-host "Export des fichiers CSV: $CSVfilename" -foregroundcolor "green"
	$out = $path + "\" + $CSVfilename
	$res | Export-csv -Path $out -NoTypeInformation
	
	############## DECONNEXION DU VCENTER
	write-host "Deconnexion du vCenter: $VC" -foregroundcolor "green"
	Disconnect-VIServer * -confirm:$false
	write-host
}
#Author Udishman Mudiar, Microsoft CSS
#The script is AS IS and is purely used for troubleshooting purpose by Microsoft CSS Team.
#How to?
#Make the changes as highlighted before running the script.
#path for output
$outputfolderpath="C:\Temp\FalseAlertETL"
#alert name
$AlertName="% free space is too low"
#principal name of the server from the Get-SCOM Alert property
#find the PrincipalName using the below command in OM Shell.
#Get-SCOMAlert -name "<Alert Name>" | Select Name,PrincipalName
#$PrincipalName= "<Server Name>"..

function Log-Trace($level, $message){
    $date=Get-Date -Format "mm/dd/yyyy-hh:mm:ss"
    $date + "  " + "[" + $level + "]" + "  " + $message | Out-File -Append $outputfolderpath\logs.txt
}

function Clean-OutputDirectory(){
    $folder=Get-Item -path $outputfolderpath -ErrorAction SilentlyContinue
    if($folder)
    {
        Remove-Item $outputfolderpath\*.* -Exclude "*.ps1" -Force
        Get-ChildItem $outputfolderpath | Remove-Item -Force
    }
    New-Item -Name OpsMgrTrace -ItemType Directory -Path $outputfolderpath | Out-Null    
}

function Import-OMModuleMS(){  
    Log-Trace "INFO" "Importing OM module.." 
    Import-Module OperationsManager
    New-SCOMManagementGroupConnection -ComputerName localhost
}

function Capture-ETL(){         
    $installdir=(Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Microsoft Operations Manager\3.0\Setup").installdirectory
    $etldir=$installdir + "tools"
    Set-Location -Path $etldir

    #stopping existing trace    
    Log-Trace "INFO" "Stopping existing trace.."
    .\StopTracing.cmd
    #removing old logs
    Remove-Item C:\Windows\Logs\OpsMgrTrace\* -Force
    #starting VERBOSE trace    
    Log-Trace "INFO" "Tracing started.."
    .\StartTracing.cmd VER

   #write the logic to stop the trace
   #e.x: when an alert is generated
   While($true)
   {                  
        try
        {            
            #"$($date1) Calling SCOM Get-SCOMAlert in loop.." >> $outputfolderpath\logs.txt
            $diskalerts = Get-SCOMAlert -Name $AlertName -ResolutionState 255 | Where-Object {$_.TimeRaised -gt (Get-Date).ToUniversalTime().AddMinutes(-10)}            
            
            for($i=0; $i -lt 1; $i++)
            {
                #sleeping for 10 minutes just to make sure we are not picking existing false alert
                Log-Trace "INFO" "Sleeping for 10 minutes to negate any false alert at start"
                Start-Sleep 600
            }

            foreach($diskalert in $diskalerts)
            {
                #if the alert is closed in next 5 min run then we are considering it to be false for now.
                if($diskalert.TimeResolved -le $diskalert.TimeRaised.AddMinutes(9))
                {
                    #$diskalert | Select Name,MonitoringObjectPath,MonitoringObjectDisplayName,TimeRaised,TimeResolved                    
                    Log-Trace "INFO" "False disk alert found"
                    $diskalert | Format-List * | Out-File $outputfolderpath\alert.txt
                }
                else{
                    #we are sleeping for 9 minutes and checking again            
                    Log-Trace "INFO" "False disk alert NOT found"
                    Log-Trace "INFO" "Sleeping for 9 minutes"
                    Start-Sleep 540            
                    Log-Trace "INFO" "Resuming after sleep" 
                }
            }                           
        }
        catch
        {
            $ErrorMessage = $_.Exception.Message
            Log-Trace "ERROR" $ErrorMessage
            #$ErrorMessage >> $outputfolderpath\logs.txt
        }         
        
        if($diskalert)
        {
            #Write-Host "Stopping ETL and copying the data to output directory" -ForegroundColor Cyan            
            Log-Trace "INFO" "Tracing stopping.."  
            .\StopTracing.cmd            
            Log-Trace "INFO" "Tracing stopped.."  
            #removing rest of the etl file as they are not required for now.
            Remove-Item -Path "C:\Windows\Logs\OpsMgrTrace\*" -Exclude "TracingGuidsNative.etl" -Force            
            Log-Trace "INFO" "Tracing formatting.."  
            #Creating a copy of the FormatTracing.cmd by replacing the string 'START %OpsMgrTracePath%'
            #This is done because if the script is used in task scheduler, we would not be able to open the folder as per the command and the script will hung.   
            Get-Content '.\FormatTracing.cmd' | Where-Object {$_ -notmatch "START %OpsMgrTracePath%"} | Set-Content '.\FormatTracing - Custom.cmd' -Force
            & '.\FormatTracing - Custom.cmd'             
            Log-Trace "INFO" "Tracing formatted.." 
            Log-Trace "INFO" "Copying formatted data.."              
            Copy-Item -Path "C:\Windows\Logs\OpsMgrTrace\*.log" -Destination "$outputfolderpath\OpsMgrTrace"            
            Log-Trace "INFO" "Copying completed.." 
            Remove-Item -Path '.\FormatTracing - Custom.cmd' -Force             
            Log-Trace "INFO" "Script ended.." 
            break            
        }
   }     
}

function Main(){    
    Clean-OutputDirectory 
    Log-Trace "INFO" "Script Started."
    Get-TimeZone | Out-File $outputfolderpath\timezone.txt
    Import-OMModuleMS
    Capture-ETL      
}

#script starts here
Main



  

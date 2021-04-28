# unraid-backup
Backup Unraid with Restic

By default this script with backup nextcloud and your set backup directories nightly. It will backup your docker containers on a Sunday night. 

You can utilise Wake-on-LAN to powerup a local server if you don't want to keep it powered on at all times. If you use a remote host, a local directory or a server that is always powered up then you can turn this feature off in the config file. 

## Prerequisits 
Restic (tested with 0.12.0)
Unraid
User Scripts plugin

For instructions on how to install restic visit https://blog.themainframe.co.uk

## Using the script
To use the script, copy the config file to somewhere you can edit it on your Unraid server and make anote of where exactly you have saved it. 

Go through the config file and change the values to fit your needs. 

Open the user scripts page and create a new script, copy the contents to of the script file and change the config location at the top of the script to where you saved your config file. Save and close the script. 

To test the script is working, click run script in the background. You can then open the log page to watch the sctript complete. 
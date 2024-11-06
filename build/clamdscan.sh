# Start watching the log file in the background to show real-time progress
echo "Starting log monitor..."
tail -f /var/log/clamav/clamd.log &
TAIL_PID=$!
echo "Monitoring log with PID: $TAIL_PID"

# Define multiple folders to scan
#SCAN_FOLDERS=" /scan/appdata /scan/system"
SCAN_FOLDERS="/scan"

# EXCLUDE_DIRS="/scan/system"
# Clamdscan uses /etc/clamd.conf for exclude folder... via regex
# since exclude is set in theory a /scan is all that is needed...

# Clear previous scan summary and logs
> /var/log/clamav/log.log  # Clear the log AV is using before scan
> /var/log/clamav/scan_summary.txt  # Make sure the infected file log is clear for the next scan

# Perform ClamDscan only on specified folders
for folder in $SCAN_FOLDERS; do
    clamdscan "$folder" --infected --verbose --multiscan --log=/var/log/clamav/log.log --stdout

#So log.log is the end of a clamdscan folder that will have a general summary overview... say if something has an infected file. however, clamd.log should now have the Found and file path...
    if grep -q FOUND /var/log/clamav/clamd.log; then
        echo "Infected file found in $folder..."
        # Capture infections...
        echo "Infected file found in $folder..." >> /var/log/clamav/scan_summary.txt
        grep FOUND /var/log/clamav/clamd.log >> /var/log/clamav/scan_summary.txt
    fi
done

# Stop the log monitor
kill $TAIL_PID

# Display Mutiple Scan Summary at end of the scan If more than one folder is scaned
#echo "Displaying Scan Summary" #uncoment if you have more then one folder set to scan
#cat /var/log/clamav/log.log    #uncoment if you have more then one folder set to scan

# Display infected files at the end of the scan
echo "Displaying any 'Found' infected files:"
cat /var/log/clamav/scan_summary.txt
exit 0

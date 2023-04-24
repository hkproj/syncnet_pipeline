# Send everything to a syslog file
#exec 1> >(logger -s -t $(basename $0)) 2>&1

delete_temp=false

# If there is a command line argument (at any position) with "--delete-temp", then set the flag to true
for var in "$@"
do
    if [ "$var" = "--delete-temp" ]; then
        delete_temp=true
    fi
done

input_dir=input
temp_dir=tmp_videos
output_dir=output
syncnet_temp=tmp_syncnet
syncnet=syncnet/demo_syncnet.py
syncnet_model=syncnet/data/syncnet_v2.model
report_file=$output_dir/report.txt

# Delete everything in temp folder only if the flag is true
if [ "$delete_temp" = true ] ; then
    echo "Deleting all files in temporary folder"
    rm -rf "$temp_dir"
fi

# Make sure all the output dirs exist
mkdir -p "$temp_dir"
mkdir -p "$output_dir"

# Make the report file empty
rm -f $report_file
touch $report_file

for entry in "$input_dir"/*
do
    if [ -f "$entry" ]; then
        # Get the filename from each file
        filename=$(basename "$entry")
        # Get the filename without extension
        filenameWithoutExtension="${filename%.*}"    

        # Get the temporary filename for the output of SyncNet
        temp_filename_syncnet="$temp_dir/$filenameWithoutExtension-syncnet.txt"

        # If the syncnet report already exists, skip this file
        if [ -f "$temp_filename_syncnet" ]; then
            echo "Skipping $filename because SyncNet report already exists"
        else
            echo "Processing $filename"

            # Clean any files in syncnet temporary folder
            rm -rf "$syncnet_temp"
            mkdir -p "$syncnet_temp"

            # Delete directory for clips if it already exists
            rm -rf "$temp_dir/$filenameWithoutExtension-clips"

            # Make directory for clips
            mkdir -p "$temp_dir/$filenameWithoutExtension-clips"

            clip_duration=59
            # Split the original file into many chunks of duration defined by $clip_duration
            # Example command: ffmpeg -i input.mp4 -c copy -map 0 -segment_time 00:00:20 -f segment -reset_timestamps 1 output%03d.mp4
            echo "Splitting original video into many chunks of $clip_duration seconds"
            temp_filename_clips="$temp_dir/$filenameWithoutExtension-clips/$filenameWithoutExtension-clip-%03d.mp4"
            ffmpeg -y -i "$entry" -c copy -map 0 -segment_time 00:00:$clip_duration -f segment -reset_timestamps 1 "$temp_filename_clips"

            for clipFilePath in "$temp_dir/$filenameWithoutExtension-clips"/*
            do
                if [ -f $clipFilePath ]; then
                    # Get the filename from each file
                    clipFileName=$(basename "$clipFilePath")
                    # Get the filename without extension
                    clipFileNameWithoutExtension="${clipFileName%.*}"    

                    echo "Changing video $clipFilePath to have 25fps"
                    # Get the temporary filename for the 25fps video
                    temp_filename_25fps="$temp_dir/$filenameWithoutExtension-clips/$clipFileNameWithoutExtension-clip-25fps.mp4"
                    # Run ffmpeg to change the FPS of the input video to 25 and save it to the output file
                    ffmpeg -y -i "$clipFilePath" -filter:v fps=25 "$temp_filename_25fps"

                    echo "Changing video $clipFilePath to have 16kHz audio"
                    # Get the temporary filename for the video with audio in 16kHz
                    temp_filename_25fps_16khz="$temp_dir/$filenameWithoutExtension-clips/$clipFileNameWithoutExtension-clip-25fps-16khz.mp4"
                    # Run ffmpeg to resample the audio at 16kHz
                    ffmpeg -y -i "$temp_filename_25fps" -ar 16000 -ac 1 "$temp_filename_25fps_16khz"

                    frame_size=224
                    echo "Resize frame of $clipFilePath to $frame_size by $frame_size"
                    # Get the temporary filename for the video with resized frame size
                    temp_filename_25fps_16khz_resized="$temp_dir/$filenameWithoutExtension-clips/$clipFileNameWithoutExtension-clip-25fps-16khz-resized.mp4"
                    # Run ffmpeg to resize the frame size
                    ffmpeg -y -i "$temp_filename_25fps_16khz" -vf scale=$frame_size:$frame_size "$temp_filename_25fps_16khz_resized"

                    echo "Running SyncNet on $clipFilePath"
                    temp_filename_clip_syncnet="$temp_dir/$filenameWithoutExtension-clips/$clipFileNameWithoutExtension-syncnet.txt"
                    # Run SyncNet on the single clip
                    python $syncnet --videofile "$temp_filename_25fps_16khz_resized" --tmp_dir $syncnet_temp --initial_model $syncnet_model > $temp_filename_clip_syncnet

                    # Print the last 3 lines of the output from SyncNet
                    echo "SyncNet output for $clipFileName:" | tee -a $temp_filename_syncnet
                    tail -n 3 $temp_filename_clip_syncnet | tee -a $temp_filename_syncnet
                    # Add blank line
                    echo "" | tee -a $temp_filename_syncnet
                fi
            done

        fi    

        echo "SyncNet output for $filename:" | tee -a $report_file
        echo "=========================================================" | tee -a $report_file
        cat $temp_filename_syncnet | tee -a $report_file
        echo "=========================================================" | tee -a $report_file
        # Add blank line
        echo "" | tee -a $report_file

    fi
done
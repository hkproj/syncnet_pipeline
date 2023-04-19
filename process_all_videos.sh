delete_temp=false

# If there is a command line argument (at any position) with "--delete-temp", then set the flag to true
for var in "$@"
do
    if [ "$var" = "--delete-temp" ]; then
        delete_temp=true
    fi
done

input_dir=input_videos
temp_dir=tmp_videos
output_dir=output_videos
syncnet_temp=tmp_syncnet
syncnet=syncnet/demo_syncnet.py
syncnet_model=syncnet/data/syncnet_v2.model
report_file=output_videos/report.txt

# Delete everything in temp folder only if the flag is true
if [ "$delete_temp" = true ] ; then
    echo "Deleting all files in temporary folder"
    rm -rf "$temp_dir"
fi

# Make sure all the output dirs exist
mkdir -p "$temp_dir"
mkdir -p "$output_dir"
mkdir -p "$syncnet_temp"

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
            clip_duration=59
            echo "Getting first $clip_duration seconds of video"
            # Get filename for the clip video
            temp_filename_clip="$temp_dir/$filenameWithoutExtension-clip.mp4"
            # Run ffmpeg to extract the first $clip_duration seconds of the original video into the clip file
            ffmpeg -y -i "$entry" -ss 00:00:00 -t 00:00:$clip_duration -c:a copy "$temp_filename_clip"

            echo "Changing video $filename to have 25fps"
            # Get the temporary filename for the 25fps video
            temp_filename_25fps="$temp_dir/$filenameWithoutExtension-clip-25fps.mp4"
            # Run ffmpeg to change the FPS of the input video to 25 and save it to the output file
            ffmpeg -y -i "$temp_filename_clip" -filter:v fps=25 "$temp_filename_25fps"

            echo "Changing video $filename to have 16kHz audio"
            # Get the temporary filename for the video with audio in 16kHz
            temp_filename_25fps_16khz="$temp_dir/$filenameWithoutExtension-clip-25fps-16khz.mp4"
            # Run ffmpeg to resample the audio at 16kHz
            ffmpeg -y -i "$temp_filename_25fps" -ar 16000 "$temp_filename_25fps_16khz"

            frame_size=224
            echo "Resize frame size to $frame_size by $frame_size"
            # Get the temporary filename for the video with resized frame size
            temp_filename_25fps_16khz_resized="$temp_dir/$filenameWithoutExtension-clip-25fps-16khz-resized.mp4"
            # Run ffmpeg to resize the frame size
            ffmpeg -y -i "$temp_filename_25fps_16khz" -vf scale=$frame_size:$frame_size "$temp_filename_25fps_16khz_resized"

            echo "Running SyncNet"
            # Run SyncNet on the video
            python $syncnet --videofile "$temp_filename_25fps_16khz_resized" --tmp_dir syncnet_temp --initial_model $syncnet_model > $temp_filename_syncnet
        fi    

        # Print the last 3 lines of the output from SyncNet
        echo "SyncNet output for $filename:" | tee -a $report_file
        tail -n 3 $temp_filename_syncnet | tee -a $report_file
        # Add blank line
        echo "" | tee -a $report_file

    fi
done
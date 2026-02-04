package core

import (
	"encoding/json"
	"fmt"
	"os/exec"
	"strconv"
	"strings"
)

type ffprobeOutput struct {
	Streams []struct {
		Width    int    `json:"width"`
		Height   int    `json:"height"`
		Duration string `json:"duration"`
	} `json:"streams"`
	Format struct {
		Duration string `json:"duration"`
	} `json:"format"`
}

// ProbeVideoMeta runs ffprobe and extracts width/height/duration.
func ProbeVideoMeta(absPath string) (int, int, float64, error) {
	cmd := exec.Command(
		"ffprobe",
		"-v",
		"error",
		"-select_streams",
		"v:0",
		"-show_entries",
		"stream=width,height,duration",
		"-show_entries",
		"format=duration,format_name",
		"-of",
		"json",
		absPath,
	)
	output, err := cmd.CombinedOutput()
	trimmedOutput := strings.TrimSpace(string(output))
	if err != nil {
		if trimmedOutput == "" {
			return 0, 0, 0, err
		}
		return 0, 0, 0, fmt.Errorf("%s", trimmedOutput)
	}

	var probe ffprobeOutput
	if err := json.Unmarshal(output, &probe); err != nil {
		if trimmedOutput == "" {
			return 0, 0, 0, err
		}
		return 0, 0, 0, fmt.Errorf("%s", trimmedOutput)
	}

	if len(probe.Streams) == 0 {
		return 0, 0, 0, fmt.Errorf("%s", trimmedOutput)
	}

	width := probe.Streams[0].Width
	height := probe.Streams[0].Height
	if width <= 0 || height <= 0 {
		return 0, 0, 0, fmt.Errorf("%s", trimmedOutput)
	}

	durationText := strings.TrimSpace(probe.Format.Duration)
	if durationText == "" || durationText == "N/A" {
		durationText = strings.TrimSpace(probe.Streams[0].Duration)
	}
	if durationText == "" || durationText == "N/A" {
		return 0, 0, 0, fmt.Errorf("%s", trimmedOutput)
	}

	durationSec, err := strconv.ParseFloat(durationText, 64)
	if err != nil {
		if trimmedOutput == "" {
			return 0, 0, 0, err
		}
		return 0, 0, 0, fmt.Errorf("%s", trimmedOutput)
	}

	return width, height, durationSec, nil
}

package core

import (
	"path"

	"gallery/common/storage"
)

var posterCoverCandidates = []string{"cover.jpg", "cover.jpeg", "cover.png", "cover.webp"}

type PosterEnqueuer interface {
	Enqueue(source string)
}

func posterCachePath(videoPath string) string {
	return videoPath + ".poster.jpg"
}

func (s *Scanner) enqueuePosterIfNeeded(videoPath string, needsRefresh bool) {
	if s == nil || s.PosterQueue == nil || videoPath == "" {
		return
	}
	if needsRefresh || !s.posterExists(videoPath) {
		s.PosterQueue.Enqueue(videoPath)
	}
}

func (s *Scanner) posterExists(videoPath string) bool {
	if s == nil || videoPath == "" {
		return false
	}

	parentDir := path.Dir(videoPath)
	for _, candidate := range posterCoverCandidates {
		coverPath := path.Join(parentDir, candidate)
		if !storage.IsValidPic(coverPath) {
			continue
		}
		if s.OriginFs != nil && s.OriginFs.Exist(coverPath) {
			return true
		}
	}

	if s.Cache == nil || s.Cache.Fs == nil {
		return false
	}
	return s.Cache.Fs.Exist(posterCachePath(videoPath))
}

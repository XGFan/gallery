package misc

import (
	"fmt"
	"log"
	"os"
	"strconv"
	"strings"
)

func StringVar(key string, defaultValue string) string {
	env, exist := os.LookupEnv(key)
	if exist {
		return env
	} else {
		return defaultValue
	}
}

func IntVar(key string, defaultValue int) int {
	stringVar := StringVar(key, fmt.Sprintf("%d", defaultValue))
	parsedValue, err := strconv.Atoi(stringVar)
	if err != nil {
		log.Printf("Env %s error :%s\n", key, stringVar)
		return defaultValue
	} else {
		return parsedValue
	}
}

func BoolVar(key string, defaultValue bool) bool {
	stringVar := StringVar(key, fmt.Sprintf("%t", defaultValue))
	// 1, 0, t, f, T, F, true, false, TRUE, FALSE, True, False
	switch strings.ToLower(stringVar) {
	case "1", "t", "true", "y", "yes", "on":
		return true
	case "0", "f", "false", "n", "no", "off":
		return false
	default:
		log.Printf("Env %s error :%s\n", key, stringVar)
		return defaultValue
	}
}

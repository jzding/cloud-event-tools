package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	log "github.com/sirupsen/logrus"
	"github.com/valyala/fasthttp"
)

var (
	// command line flags
	webhookURL        = flag.String("url", "http://localhost:9087/webhook", "Target webhook URL for cloud events")
	avgMessagesPerSec = flag.Int("rate", 10, "Average messages per second")
	testDuration      = flag.Int("duration", 10, "Test duration in seconds")
	initialDelay      = flag.Int("delay", 10, "Initial delay in seconds when starting")
	checkResp         = flag.String("check-resp", "YES", "Check response from server (YES/NO/MULTI_THREAD)")
	withMsgField      = flag.String("with-msg", "YES", "Include message field in events (YES/NO)")
	perf              = flag.String("perf", "NO", "Run performance test (YES/NO)")
	dataDir           = flag.String("data-dir", "data/", "Directory containing test event files")
	eventFile         = flag.String("event-file", "", "Specific event file to send (overrides data-dir)")
	help              = flag.Bool("help", false, "Show help message")

	totalPerSecMsgCount uint64 = 0
	wg                  sync.WaitGroup
	tck                 *time.Ticker
)

func main() {
	flag.Parse()
	initLogger()

	if *help {
		showHelp()
		return
	}

	// Override flags with environment variables if set (for backward compatibility)
	if envWebhookURL := os.Getenv("TEST_DEST_URL"); envWebhookURL != "" {
		*webhookURL = envWebhookURL
	}
	if envMsgPerSec := os.Getenv("MSG_PER_SEC"); envMsgPerSec != "" {
		if rate, err := strconv.Atoi(envMsgPerSec); err == nil {
			*avgMessagesPerSec = rate
		}
	}
	if envTestDuration := os.Getenv("TEST_DURATION_SEC"); envTestDuration != "" {
		if duration, err := strconv.Atoi(envTestDuration); err == nil {
			*testDuration = duration
		}
	}
	if envInitialDelay := os.Getenv("INITIAL_DELAY_SEC"); envInitialDelay != "" {
		if delay, err := strconv.Atoi(envInitialDelay); err == nil {
			*initialDelay = delay
		}
	}
	if envCheckResp := os.Getenv("CHECK_RESP"); envCheckResp != "" {
		*checkResp = envCheckResp
	}
	if envWithMsgField := os.Getenv("WITH_MESSAGE_FIELD"); envWithMsgField != "" {
		*withMsgField = envWithMsgField
	}
	if envPerf := os.Getenv("PERF"); envPerf != "" {
		*perf = envPerf
	}

	log.Infof("Cloud Event Tester starting...")
	log.Infof("Target URL: %s", *webhookURL)
	log.Infof("Test Mode: %s", func() string {
		if strings.ToUpper(*perf) == "YES" {
			return "Performance"
		}
		return "Basic"
	}())

	if strings.ToUpper(*perf) == "YES" {
		perfTest()
	} else {
		basicTest()
	}
}

func showHelp() {
	fmt.Println("Cloud Event Tester - A standalone tool for testing cloud events")
	fmt.Println("")
	fmt.Println("Usage:")
	fmt.Printf("  %s [options]\n", os.Args[0])
	fmt.Println("")
	fmt.Println("Options:")
	flag.PrintDefaults()
	fmt.Println("")
	fmt.Println("Environment Variables (override flags):")
	fmt.Println("  TEST_DEST_URL         - Target webhook URL")
	fmt.Println("  MSG_PER_SEC          - Messages per second")
	fmt.Println("  TEST_DURATION_SEC    - Test duration in seconds")
	fmt.Println("  INITIAL_DELAY_SEC    - Initial delay in seconds")
	fmt.Println("  CHECK_RESP           - Check response (YES/NO/MULTI_THREAD)")
	fmt.Println("  WITH_MESSAGE_FIELD   - Include message field (YES/NO)")
	fmt.Println("  PERF                 - Performance test mode (YES/NO)")
	fmt.Println("  LOG_LEVEL           - Log level (debug, info, warn, error)")
	fmt.Println("")
	fmt.Println("Examples:")
	fmt.Println("  # Send all events in data directory")
	fmt.Println("  ./cloud-event-tester -url http://localhost:8080/webhook")
	fmt.Println("")
	fmt.Println("  # Send a specific event file")
	fmt.Println("  ./cloud-event-tester -url http://localhost:8080/webhook -event-file data/TMP0100.json")
	fmt.Println("")
	fmt.Println("  # Run performance test")
	fmt.Println("  ./cloud-event-tester -url http://localhost:8080/webhook -perf YES -rate 50 -duration 60")
}

func initLogger() {
	lvl, ok := os.LookupEnv("LOG_LEVEL")
	// LOG_LEVEL not set, let's default to debug
	if !ok {
		lvl = "debug"
	}
	// parse string, this is built-in feature of logrus
	ll, err := log.ParseLevel(lvl)
	if err != nil {
		ll = log.DebugLevel
	}
	// set global log level
	log.SetLevel(ll)
}

func basicTest() {
	var files []string
	var err error

	if *eventFile != "" {
		// Send a specific file
		files = []string{*eventFile}
		log.Infof("Testing with specific event file: %s", *eventFile)
	} else {
		// Send all JSON files in data directory
		files, err = filepath.Glob(*dataDir + "*.json")
		if err != nil {
			log.Fatal(err)
		}
		log.Infof("Testing with %d event files from directory: %s", len(files), *dataDir)
	}

	if len(files) == 0 {
		log.Fatalf("No event files found to test")
	}

	req := fasthttp.AcquireRequest()
	req.Header.SetContentType("application/json")
	req.Header.SetMethod("POST")
	req.SetRequestURI(*webhookURL)
	res := fasthttp.AcquireResponse()
	defer fasthttp.ReleaseRequest(req)

	successCount := 0
	for i, file := range files {
		event, err := os.ReadFile(file)
		if err != nil {
			log.Errorf("Failed to read file %s: %v", file, err)
			continue
		}

		log.Infof("[%d/%d] Sending event from file: %s", i+1, len(files), filepath.Base(file))
		log.Debugf("Event content: %s", string(event))

		req.SetBody(event)
		if err := fasthttp.Do(req, res); err != nil {
			log.Errorf("Failed to send event: %v", err)
		} else {
			log.Infof("Event sent successfully, response status: %d", res.StatusCode())
			if res.StatusCode() >= 200 && res.StatusCode() < 300 {
				successCount++
			}
		}
		time.Sleep(time.Second)
	}

	log.Infof("Basic test completed. Successfully sent %d/%d events", successCount, len(files))
}

func perfTest() {
	// Use default event file or specified one
	defaultEventFile := filepath.Join(*dataDir, "TMP0100.json")
	noMsgFieldFile := filepath.Join(*dataDir, "TMP0100-no-msg-field.json")

	if *eventFile != "" {
		defaultEventFile = *eventFile
		// For single file, create a no-msg version by removing the Message field
		noMsgFieldFile = *eventFile
	}

	eventTMP0100, err := os.ReadFile(defaultEventFile)
	if err != nil {
		log.Fatalf("Failed to read event file %s: %v", defaultEventFile, err)
	}

	eventTMP0100NoMsgField, err := os.ReadFile(noMsgFieldFile)
	if err != nil {
		log.Warnf("Failed to read no-msg-field file %s, using default: %v", noMsgFieldFile, err)
		// If no-msg-field file doesn't exist, use the default event
		eventTMP0100NoMsgField = eventTMP0100
	}

	log.Infof("=== Performance Test Configuration ===")
	log.Infof("Webhook URL: %v", *webhookURL)
	log.Infof("Messages Per Second: %d", *avgMessagesPerSec)
	log.Infof("Test Duration: %d seconds", *testDuration)
	log.Infof("Initial Delay: %d seconds", *initialDelay)
	log.Infof("CHECK_RESP: %v", *checkResp)
	log.Infof("WITH_MESSAGE_FIELD: %v", *withMsgField)
	log.Infof("Event File: %s", defaultEventFile)

	log.Infof("Sleeping %d sec...", *initialDelay)
	time.Sleep(time.Duration(*initialDelay) * time.Second)

	// how many milliseconds one message takes
	avgMsgPeriodInMs := 1000 / *avgMessagesPerSec
	log.Debugf("avgMsgPeriodInMs: %d", avgMsgPeriodInMs)
	midpoint := avgMsgPeriodInMs / 2

	log.Debugf("midpoint: %d", midpoint)

	totalSeconds := 0
	totalMsg := 0

	req := fasthttp.AcquireRequest()
	req.Header.SetContentType("application/json")
	req.Header.SetMethod("POST")
	if strings.ToUpper(*withMsgField) == "YES" {
		req.SetBody(eventTMP0100)
	} else if strings.ToUpper(*withMsgField) == "NO" {
		req.SetBody(eventTMP0100NoMsgField)
	} else {
		log.Errorf("WITH_MESSAGE_FIELD=%v is not a valid value", *withMsgField)
		os.Exit(1)
	}
	req.SetRequestURI(*webhookURL)
	res := fasthttp.AcquireResponse()

	wg.Add(1)
	go func() {
		defer wg.Done()
		for range time.Tick(time.Second) {
			if totalSeconds >= *testDuration {
				tck.Stop()
				fasthttp.ReleaseRequest(req)
				totalSeconds--
				log.Info("******** Performance Test Completed ********")
				log.Infof("Total Seconds : %d", totalSeconds)
				log.Infof("Total Msg Sent: %d", totalMsg)
				if totalSeconds > 0 {
					log.Infof("Average Msg/Second: %2.2f", float64(totalMsg)/float64(totalSeconds))
				}
				os.Exit(0)
			}
			log.Debugf("|Total message sent mps:|%2.2f|", float64(totalPerSecMsgCount))
			totalPerSecMsgCount = 0
			totalSeconds++
		}
	}()

	log.Infof("******** Performance Test Started ********")
	// log these again for convenient of splitting logs
	log.Infof("Webhook URL: %v", *webhookURL)
	log.Infof("Messages Per Second: %d", *avgMessagesPerSec)
	log.Infof("Test Duration: %d seconds", *testDuration)
	log.Infof("Initial Delay: %d seconds", *initialDelay)
	log.Infof("CHECK_RESP: %v", *checkResp)

	// 1ms ticker
	tck = time.NewTicker(time.Duration(1000*avgMsgPeriodInMs) * time.Microsecond)
	for range tck.C {
		checkRespUpper := strings.ToUpper(*checkResp)
		if checkRespUpper == "YES" {
			totalMsg++
			if err := fasthttp.Do(req, res); err != nil {
				totalMsg--
				log.Errorf("Sending error: %v", err)
			}
		} else if checkRespUpper == "NO" {
			totalMsg++
			fasthttp.Do(req, res) //nolint: errcheck
		} else if checkRespUpper == "MULTI_THREAD" {
			wg.Add(1)
			go func() {
				defer wg.Done()
				totalMsg++
				if err := fasthttp.Do(req, res); err != nil {
					log.Errorf("Sending error: %v", err)
					totalMsg--
				}
			}()
		} else {
			log.Errorf("CHECK_RESP=%v is not a valid value", *checkResp)
			os.Exit(1)
		}
		totalPerSecMsgCount++
	}
}

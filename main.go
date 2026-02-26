package main

import (
	"bytes"
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"time"

	"tailscale.com/tsnet"
)

// ConfigResponse is the JSON envelope returned by GET /api/config.
type ConfigResponse struct {
	Config string `json:"config"`
	Exists bool   `json:"exists"`
	Hash   string `json:"hash"`
}

// ConfigUpdate is the JSON envelope for PUT /api/config.
type ConfigUpdate struct {
	Config string `json:"config"`
	Hash   string `json:"hash"`
}

func main() {
	var (
		hostname = flag.String("hostname", "aperture-bootstrap", "Tailscale hostname for the ephemeral node")
		target   = flag.String("target", "http://ai/api/config", "Aperture config API URL")
		read     = flag.Bool("read", false, "Read current Aperture config and print it")
		write    = flag.String("write", "", "Path to JSON config file to push (requires -hash)")
		hash     = flag.String("hash", "", "OCC hash from a previous read (required for -write)")
	)
	flag.Parse()

	if !*read && *write == "" {
		fmt.Fprintln(os.Stderr, "Usage:")
		fmt.Fprintln(os.Stderr, "  aperture-bootstrap -read")
		fmt.Fprintln(os.Stderr, "  aperture-bootstrap -write config.json -hash <hash>")
		os.Exit(1)
	}

	authKey := os.Getenv("TS_AUTHKEY")
	if authKey == "" {
		log.Fatal("TS_AUTHKEY environment variable is required (ephemeral, no-tag auth key)")
	}

	// tsnet gives us a proper Tailscale node identity.
	// This is the key insight: kernel-level HTTP from tagged devices
	// does not present WhoIs identity correctly to Aperture.
	// tsnet's HTTPClient() does.
	dir, err := os.MkdirTemp("", "aperture-bootstrap-*")
	if err != nil {
		log.Fatalf("mkdirtemp: %v", err)
	}
	defer os.RemoveAll(dir)

	srv := &tsnet.Server{
		Hostname:  *hostname,
		Ephemeral: true,
		AuthKey:   authKey,
		Dir:       dir,
	}
	defer srv.Close()

	log.Printf("Connecting to tailnet as %q (ephemeral, user-owned)...", *hostname)
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	if _, err := srv.Up(ctx); err != nil {
		log.Fatalf("tsnet.Up: %v", err)
	}
	log.Println("Connected.")

	client := srv.HTTPClient()
	client.Timeout = 15 * time.Second

	if *read {
		doRead(client, *target)
	} else {
		doWrite(client, *target, *write, *hash)
	}
}

func doRead(client *http.Client, target string) {
	resp, err := client.Get(target)
	if err != nil {
		log.Fatalf("GET %s: %v", target, err)
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != 200 {
		log.Fatalf("GET %s: %d %s", target, resp.StatusCode, string(body))
	}

	var cr ConfigResponse
	if err := json.Unmarshal(body, &cr); err != nil {
		log.Fatalf("parse response: %v", err)
	}

	// Pretty-print the inner config JSON.
	var pretty json.RawMessage
	if err := json.Unmarshal([]byte(cr.Config), &pretty); err != nil {
		// Not valid JSON — print raw.
		fmt.Println(cr.Config)
	} else {
		enc := json.NewEncoder(os.Stdout)
		enc.SetIndent("", "  ")
		enc.Encode(pretty)
	}

	fmt.Fprintf(os.Stderr, "\nhash: %s\n", cr.Hash)
}

func doWrite(client *http.Client, target, configPath, hash string) {
	if hash == "" {
		log.Fatal("-hash is required for -write (run -read first to get it)")
	}

	configBytes, err := os.ReadFile(configPath)
	if err != nil {
		log.Fatalf("read %s: %v", configPath, err)
	}

	// Validate it's valid JSON.
	var check json.RawMessage
	if err := json.Unmarshal(configBytes, &check); err != nil {
		log.Fatalf("%s is not valid JSON: %v", configPath, err)
	}

	update := ConfigUpdate{
		Config: string(configBytes),
		Hash:   hash,
	}
	payload, _ := json.Marshal(update)

	req, err := http.NewRequest("PUT", target, bytes.NewReader(payload))
	if err != nil {
		log.Fatalf("NewRequest: %v", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := client.Do(req)
	if err != nil {
		log.Fatalf("PUT %s: %v", target, err)
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != 200 {
		log.Fatalf("PUT %s: %d %s", target, resp.StatusCode, string(body))
	}

	var result map[string]interface{}
	json.Unmarshal(body, &result)

	log.Printf("Config saved. New hash: %v", result["hash"])
}

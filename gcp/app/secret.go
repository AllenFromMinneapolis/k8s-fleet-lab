package main

import (
	"context"
	"errors"
	"os"
	"strings"

	secretmanager "cloud.google.com/go/secretmanager/apiv1"
	"cloud.google.com/go/secretmanager/apiv1/secretmanagerpb"
)

// loadAPIKey reads the API key from Google Secret Manager. On GKE the pod proves who it is
// with Workload Identity, so there's no key file or password in the code, image or Git.
// For a local run without GCP, set API_KEY instead.
func loadAPIKey(ctx context.Context) (string, error) {
	name := os.Getenv("SECRET_NAME") // projects/<project>/secrets/<secret>/versions/latest
	if name == "" {
		if key := os.Getenv("API_KEY"); key != "" {
			return key, nil
		}
		return "", errors.New("set SECRET_NAME (on GCP) or API_KEY (local run)")
	}

	client, err := secretmanager.NewClient(ctx)
	if err != nil {
		return "", err
	}
	defer client.Close()

	resp, err := client.AccessSecretVersion(ctx, &secretmanagerpb.AccessSecretVersionRequest{Name: name})
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(resp.Payload.Data)), nil
}

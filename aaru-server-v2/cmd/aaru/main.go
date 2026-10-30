// Command aaru is the Aaru API server.
//
//	aaru --http-host 0.0.0.0 --http-port 8080   serve
//	aaru --db-migrate                            apply migrations and exit
//	aaru --anime-mappings default                load anime_mappings and exit
package main

import (
	"aaru-go-api/internal/app"
	"context"
	"fmt"
	"os"
	"os/signal"
	"syscall"
)

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	if err := app.Run(ctx, os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

// Copyright (c) 2021 Gitpod GmbH. All rights reserved.
// Licensed under the GNU Affero General Public License (AGPL).
// See License-AGPL.txt in the project root for license information.

package cmd

import (
	"context"
	"fmt"
	"os"
	"strings"
	"time"

	log "github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
	"google.golang.org/grpc"

	serverapi "github.com/gitpod-io/gitpod/gitpod-protocol"
	supervisor "github.com/gitpod-io/gitpod/supervisor/api"
)

var (
	user        string
	token       string
	tokenScopes string
	host        string
	repoURL     string
	gitCommand  string
)

var gitTokenValidator = &cobra.Command{
	Use:    "git-token-validator",
	Short:  "Gitpod's Git token validator",
	Long:   "Tries to guess the scopes needed for a git operation and requests an appropriate token.",
	Args:   cobra.ExactArgs(0),
	Hidden: true,
	Run: func(cmd *cobra.Command, args []string) {
		log.Infof("gp git-token-validator")

		ctx, cancel := context.WithTimeout(context.Background(), 1*time.Minute)
		defer cancel()
		supervisorAddr := os.Getenv("SUPERVISOR_ADDR")
		if supervisorAddr == "" {
			supervisorAddr = "localhost:22999"
		}
		supervisorConn, err := grpc.Dial(supervisorAddr, grpc.WithInsecure())
		if err != nil {
			log.WithError(err).Fatal("error connecting to supervisor")
		}
		wsinfo, err := supervisor.NewInfoServiceClient(supervisorConn).WorkspaceInfo(ctx, &supervisor.WorkspaceInfoRequest{})
		if err != nil {
			log.WithError(err).Fatal("error getting workspace info from supervisor")
		}
		clientToken, err := supervisor.NewTokenServiceClient(supervisorConn).GetToken(ctx, &supervisor.GetTokenRequest{
			Host: wsinfo.GitpodApi.Host,
			Kind: "gitpod",
			Scope: []string{
				"function:guessGitTokenScopes",
			},
		})
		if err != nil {
			log.WithError(err).Fatal("error getting token from supervisor")
		}
		client, err := serverapi.ConnectToServer(wsinfo.GitpodApi.Endpoint, serverapi.ConnectToServerOpts{Token: clientToken.Token, Context: ctx})
		if err != nil {
			log.WithError(err).Fatal("error connecting to server")
		}
		params := &serverapi.GuessGitTokenScopesParams{
			Host:       host,
			RepoURL:    repoURL,
			GitCommand: gitCommand,
			CurrentToken: &serverapi.GitToken{
				Token:  token,
				Scopes: strings.Split(tokenScopes, ","),
				User:   user,
			},
		}
		guessedTokenScopes, err := client.GuessGitTokenScopes(ctx, params)
		if err != nil {
			log.WithError(err).Fatal("error guessing token scopes on server")
		}
		if guessedTokenScopes.Message != "" {
			message := fmt.Sprintf("%s Please check the permissions on the [access control page](%s/access-control).", guessedTokenScopes.Message, wsinfo.GetGitpodHost())
			_, err := supervisor.NewNotificationServiceClient(supervisorConn).Notify(ctx,
				&supervisor.NotifyRequest{
					Level:   supervisor.NotifyRequest_ERROR,
					Message: message,
				})
			log.WithError(err).Fatalf("error notifying client: '%s'", message)
		}

		_, err = supervisor.NewTokenServiceClient(supervisorConn).GetToken(ctx,
			&supervisor.GetTokenRequest{
				Host:        host,
				Scope:       guessedTokenScopes.Scopes,
				Description: "",
				Kind:        "git",
			})
		if err != nil {
			log.WithError(err).Fatal("error getting new token from token service")
			return
		}
	},
}

func init() {
	rootCmd.AddCommand(gitTokenValidator)
	gitTokenValidator.Flags().StringVarP(&user, "user", "u", "", "Git user")
	gitTokenValidator.Flags().StringVarP(&token, "token", "t", "", "The Git token to be validated")
	gitTokenValidator.Flags().StringVarP(&tokenScopes, "scopes", "s", "", "A comma spearated list of the scopes of given token")
	gitTokenValidator.Flags().StringVar(&host, "host", "", "The Git host")
	gitTokenValidator.Flags().StringVarP(&repoURL, "repoURL", "r", "", "The URL of the Git repository")
	gitTokenValidator.Flags().StringVarP(&gitCommand, "gitCommand", "c", "", "The Git command to be performed")
	gitTokenValidator.MarkFlagRequired("user")
	gitTokenValidator.MarkFlagRequired("token")
	gitTokenValidator.MarkFlagRequired("scopes")
	gitTokenValidator.MarkFlagRequired("host")
	gitTokenValidator.MarkFlagRequired("repoURL")
	gitTokenValidator.MarkFlagRequired("gitCommand")
}

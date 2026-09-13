// A cobra root command that is built and executed with no args. This is the
// shape api-cli's own entry point has, minus the config.
package main

import (
	"os"

	"github.com/spf13/cobra"
)

func main() {
	root := &cobra.Command{
		Use:           "probe",
		SilenceUsage:  true,
		SilenceErrors: true,
		RunE: func(c *cobra.Command, args []string) error {
			os.Stdout.WriteString("hello\n")
			return nil
		},
	}
	root.PersistentFlags().String("config", "", "config path")
	root.SetArgs(nil)
	_ = root.Execute()
}

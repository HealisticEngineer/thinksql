module.exports = {
  platform: 'github',
  token: process.env.RENOVATE_TOKEN,
  repositories: ['HealisticEngineer/thinksql'],
  dryRun: null,
  binarySource: "install",
  onboardingConfig: {
    $schema: "https://docs.renovatebot.com/renovate-schema.json",
    extends: ["config:best-practices"],
    postUpdateOptions: ["gomodTidy"],
    
    // 1. Add a custom note to the body of every PR
    prBodyNotes: [
      "⚠️ **Note for Go Developers**: This PR has been automatically tidied using `go mod tidy`.",
      "Please verify the `go.sum` changes before merging."
    ],

    // 2. Add a header (great for internal links or policy reminders)
    prHeader: "Internal Task: Update Golang Dependencies",

    packageRules: [
      {
        matchManagers: ["gomod"],
        matchDepTypes: ["indirect"],
        enabled: true
      },
      // 3. You can even customize comments for SPECIFIC packages
      {
        matchPackageNames: ["github.com/denisenkom/go-mssqldb"],
        prBodyNotes: ["This is a core database driver. Ensure SQL Server 2022 compatibility is verified."]
      }
    ]
  }
};
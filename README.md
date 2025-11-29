# 🚀 LauGit: The Enhanced Git Workflow Tool

LauGit (LG) is a **BASH shell script** wrapper designed to simplify common and complex **Git** operations via an interactive, color-coded menu system or a direct Command Line Interface (CLI). It helps manage your local Git repository and sync changes with a remote GitHub repository securely using Personal Access Tokens (PATs).

-----

## ✨ Features

  * **Secure Credential Management:** Stores GitHub Username and PAT in a secure, mode-600 JSON file (`.config/laugit/credentials.json`).
  * **Guided Workflows:** Offers step-by-step interactive menus for common tasks like initial setup, committing, branching, and pushing.
  * **Enhanced Logging:** Logs all Git command executions and status to `.local/state/laugit/logs/laugit.log`.
  * **Dependency Check:** Automatically checks for and attempts to install necessary dependencies (`git`, `jq`, `sed`, `less`, `curl`).
  * **Convenience Utilities:** Includes tools for building `.gitignore` files and automated push/commit sequences.

-----

## 🛠️ Requirements & Installation

### Prerequisites

  * **Bash Environment:** The script requires a UNIX-like shell environment (Linux, macOS, WSL).
  * **Dependencies:** `git`, `jq`, `sed`, `less`, `curl`. The script will attempt to install them on Debian/RedHat-based systems.

### Installation

1.  **Save the Script:** Save the provided code into a file, for example, `laugit.sh`.
2.  **Make Executable:** Set the execution permission.
    ```bash
    chmod +x laugit.sh
    ```
3.  **Run the Tool:**
    ```bash
    ./laugit.sh
    ```
    > 💡 **Tip:** For easy access, you can move the script to a directory in your `$PATH` (e.g., `/usr/local/bin`) and rename it to `laugit`.

-----

## ⚙️ Initial Setup & Configuration

Upon first launch, the tool performs a dependency check and guides you through setting up your Git user and GitHub credentials.

### 1\. Configure Global Git User Info (Name/Email)

The script automatically prompts for this if missing, or you can access it via the **User Profile Menu (P)**.

  * **Action:** Sets your global `user.name` and `user.email`.
  * **Command:** `git config --global user.name "Your Name"` and `git config --global user.email "your.email@example.com"`

### 2\. Add/Update GitHub Credentials

Use **Main Menu Option [P] -\> [1] Add/Update GitHub Credentials**.

  * **Input:** You'll be prompted for your **GitHub Username** and **Personal Access Token (PAT)**.
  * **Security:** The PAT is used to authenticate remote operations (Clone, Push, Initial Setup) by temporarily injecting it into the remote URL. It is stored in a secured file.
  * **Verification:** The script verifies the token's validity by attempting a connection to the GitHub API.

-----

## 💡 Interactive Workflow Options

The tool provides an interactive menu for a range of Git operations.

### I. Local Setup & Management

| Option | Function | Description |
| :---: | :--- | :--- |
| **[1]** | **Initial Setup & Push** | **Guided workflow** to: 1. Create a local folder. 2. Initialize a Git repo (`git init`). 3. Add and commit all files. 4. Prompt for a new GitHub HTTPS URL. 5. Set remote and force-push the branch using your PAT. |
| **[2]** | **Clone Repository** | Prompts for a repository URL and an optional destination folder, then executes `git clone`. |
| **[3]** | **Local Operations Menu** | Accesses all local Git commands (Status, Add, Commit, History, Diff, Undo, Stash, Tag). |
| **[4]** | **Branching Menu** | Accesses branch management commands (List, Create/Switch, Merge, Rebase, Delete). |

### II. Sync & Workflows

| Option | Function | Description |
| :---: | :--- | :--- |
| **[5]** | **Auto Sync** | Executes a sequence: `git add .` -\> `git commit -m "AutoSync: [timestamp]"` (if changes exist) -\> `git push origin [current-branch]`. |
| **[6]** | **Quick Commit & Push** | Prompts for a custom commit message, then executes: `git add .` -\> `git commit -m "[message]"` (if changes exist) -\> `git push origin [current-branch]`. |
| **[7]** | **Push Commits** | Prompts to check if a `--force-with-lease` push is needed, then executes `git push origin [current-branch]`. Automatically prompts to set upstream if needed. |
| **[8]** | **Pull Changes** | Prompts whether to use `--rebase` or default merge, then executes `git pull [rebase/merge] origin [current-branch]`. |

### III. Configuration & Utilities

| Option | Function | Description |
| :---: | :--- | :--- |
| **[9]** | **Remote Config Menu** | Sub-menu to list, change URL, remove, add, or prune remotes. |
| **[P]** | **User Profile Menu** | Sub-menu to manage Git User Info and GitHub Credentials (Add/Update/View). |
| **[G]** | **Build .gitignore** | Presents a selection of common templates (Python, Node, macOS, etc.) to generate or append to your local `.gitignore` file. |

-----

## 💻 Direct CLI Commands

LauGit supports several one-shot commands directly from the shell, bypassing the interactive menu.

| CLI Command | Equivalent Action | Underlying Git Commands |
| :--- | :--- | :--- |
| `./laugit.sh status` | Local Operations -\> Status | `git status` |
| `./laugit.sh add [path]` | Local Operations -\> Add | `git add [path]` (defaults to `.`) |
| `./laugit.sh commit "message"` | Local Operations -\> Commit | `git commit -m "message"` |
| `./laugit.sh push` | Sync -\> Push Commits | `git push origin [current-branch]` |
| `./laugit.sh pull` | Sync -\> Pull Changes | `git pull origin [current-branch]` (using merge) |
| `./laugit.sh pull rebase` | Sync -\> Pull Changes (Rebase) | `git pull --rebase origin [current-branch]` |
| `./laugit.sh init` | Local Setup -\> Initial Setup | Interactive `init_and_push` workflow. |
| `./laugit.sh clone` | Local Setup -\> Clone Repository | Interactive `clone_repo` workflow. |
| `./laugit.sh quick` | Sync -\> Quick Commit & Push | Interactive `quick_workflow` (prompts for message). |

### Example CLI Usage

```bash
# Add all and commit with a message
./laugit.sh add .
./laugit.sh commit "feat: implemented new API endpoint"

# Pull with rebase
./laugit.sh pull rebase

# Hard push (Use with caution!)
./laugit.sh push --force
```

-----

## ⚠️ Security Note

The script uses Personal Access Tokens (PAT) for remote operations. The token is stored locally in plain text within a dedicated configuration file (`.config/laugit/credentials.json`). **The script automatically sets the file permissions to `600`** (readable/writable only by the owner). Ensure your local environment is secure, as this file contains sensitive credentials.

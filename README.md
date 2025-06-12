# tunnelctl

`🔐 tunnelctl` is a simple, portable SSH tunnel manager for commonly used services like Postgres, MongoDB, Redis, and Elasticsearch. It supports background mode, port overrides, tunnel viewing/killing, and zero config files.

---

## 🚀 Installation (one-liner)

```bash
mkdir -p ~/bin && curl -sSL https://raw.githubusercontent.com/n1818r/tunnelctl/main/tunnelctl.sh -o ~/bin/tunnelctl && chmod +x ~/bin/tunnelctl
```

### 🔧 Add ~/bin to your PATH (if not already)

For bash:

```bash
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc
```

For zsh:

```bash
echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc && source ~/.zshrc
```

---

## 🛠️ Usage Examples

### 🔌 Start a tunnel for Postgres:

```bash
tunnelctl --service postgres --key ~/.ssh/your-key.pem
```

### 🔌 Start multiple tunnels:

```bash
tunnelctl --service postgres --service redis --key ~/.ssh/your-key.pem
```

### 👀 Show active tunnels:

```bash
tunnelctl --show
```

### 🔪 Kill active tunnels:

```bash
tunnelctl --kill all
```

### ⚙️ Configure SSH user and host (updates inside script itself):

```bash
tunnelctl --configure user=ec2-user,host=ec2-11-22-33-44.compute.amazonaws.com
```

### 📋 Show current SSH configuration:

```bash
tunnelctl --configure show
```

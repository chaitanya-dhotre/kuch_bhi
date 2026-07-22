
# kuch_bhi

A private encrypted messaging app for friends

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.





sudo tee /etc/systemd/system/kuchbhi-fcm.service << 'EOF'
[Unit]
Description=Kuch Bhi FCM Notification Service
After=network.target pocketbase.service
Requires=pocketbase.service

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/kuchbhi
ExecStart=/usr/bin/python3 /opt/kuchbhi/fcm_service.py
Restart=always
RestartSec=5

# PocketBase admin credentials — set via a secrets file, NEVER commit real values.
# Store them in /etc/kuchbhi.env (chmod 600, git-ignored) and load with EnvironmentFile.
Environment="PB_ADMIN_EMAIL=your-admin@example.com"
Environment="PB_ADMIN_PASSWORD=CHANGE_ME_USE_SECRETS_FILE"

StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable kuchbhi-fcm
sudo systemctl start kuchbhi-fcm
sudo systemctl status kuchbhi-fcm
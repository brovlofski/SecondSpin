# Installation Guide for VinylVault

This guide will help you install VinylVault on your iPhone 12 using your MacBook. The app is not available on the App Store, so we'll install it directly from the source code using Xcode.

## 📋 Prerequisites

Before you begin, make sure you have:

### Hardware Requirements:
- **MacBook** (any model that can run macOS Sonoma or later)
- **iPhone 12** (with iOS 17.0 or later)
- **USB-C to Lightning cable** (to connect your iPhone to your MacBook)

### Software Requirements:
- **macOS Sonoma (14.0) or later** - [Check your macOS version](https://support.apple.com/en-us/HT201260)
- **Xcode 15.0 or later** - [Download from Mac App Store](https://apps.apple.com/us/app/xcode/id497799835)
- **Apple Developer Account** (free) - We'll create this in the guide
- **Git** (comes with Xcode)

## 🚀 Step-by-Step Installation

### Step 1: Check Your macOS Version

1. Click the **Apple menu** (🍎) in the top-left corner of your screen
2. Select **About This Mac**
3. Look for the **macOS version** number
4. **If it's Sonoma (14.0) or later**, you're good to go!
5. **If it's older**, you need to update:
   - Go to **System Settings** → **General** → **Software Update**
   - Install any available updates

### Step 2: Install Xcode

1. Open the **App Store** on your MacBook
2. Search for **"Xcode"** in the search bar
3. Click the **Get** button (it's free)
4. Wait for it to download and install (this may take 30-60 minutes)
5. Once installed, open Xcode from your Applications folder
6. On first launch, agree to the license agreement
7. Let Xcode install additional components (this may take a few minutes)

### Step 3: Create a Free Apple Developer Account

You need this to install apps on your iPhone:

1. Open **Xcode**
2. Go to **Xcode** menu → **Settings** (or **Preferences**)
3. Click the **Accounts** tab
4. Click the **+** button in the bottom-left corner
5. Select **Apple ID** and click **Continue**
6. Sign in with your **Apple ID** (the same one you use for iCloud)
7. If prompted, agree to the Apple Developer Agreement
8. Wait for Xcode to set up your account

### Step 4: Download the VinylVault Source Code

1. Open **Safari** on your MacBook
2. Go to: `https://github.com/brovlofski/SecondSpin`
3. Click the green **Code** button
4. Click **Download ZIP**
5. The file will download to your **Downloads** folder
6. Double-click the downloaded ZIP file to extract it
7. You should now have a folder called `SecondSpin-main`

### Step 5: Prepare Your iPhone

1. **Unlock** your iPhone 12
2. Connect your iPhone to your MacBook using the USB-C to Lightning cable
3. On your iPhone, if you see **"Trust This Computer?"**, tap **Trust**
4. Enter your iPhone passcode if prompted
5. On your Mac, you should see your iPhone appear in Finder

### Step 6: Open the Project in Xcode

1. Open **Xcode** on your MacBook
2. Go to **File** → **Open...**
3. Navigate to your **Downloads** folder → **SecondSpin-main** folder
4. Select **SecondSpin.xcodeproj** (the blue icon)
5. Click **Open**

### Step 7: Configure the Project for Your iPhone

1. In Xcode, look at the top toolbar
2. Find the device selector (it probably says "iPhone 17" or similar)
3. Click it and select **Your iPhone's Name** (it should appear in the list)
4. If you don't see your iPhone:
   - Make sure it's connected and unlocked
   - Try disconnecting and reconnecting the cable
   - Restart Xcode if needed

### Step 8: Set Up Signing (Most Important Step!)

This tells Apple that you're allowed to install this app:

1. In Xcode, in the left sidebar, click **SecondSpin** (the top item)
2. In the main area, click **VinylVault** under **TARGETS**
3. Click the **Signing & Capabilities** tab
4. Under **Signing**, check **"Automatically manage signing"**
5. Select your **Personal Team** from the dropdown
6. You might see a warning - that's normal
7. Xcode will automatically create certificates for you

### Step 9: Build and Run the App

1. Click the **Play button** (▶) in the top-left corner of Xcode
2. **First time only**: You'll see an error about "No matching provisioning profiles"
3. Don't worry! Just click the **Play button** (▶) again
4. On your iPhone, you might see: **"Untrusted Developer"**
5. On your iPhone, go to: **Settings** → **General** → **VPN & Device Management**
6. Under **Developer App**, tap your **Apple ID email**
7. Tap **Trust "[Your Email]"**
8. Tap **Trust** again to confirm
9. Go back to Xcode and click the **Play button** (▶) one more time

### Step 10: Wait for Installation

1. Xcode will now:
   - Build the app (compile the code)
   - Install it on your iPhone
   - Launch it automatically
2. This may take 2-5 minutes the first time
3. You'll see progress in Xcode's top bar
4. On your iPhone, the VinylVault app icon will appear
5. The app will open automatically when installation is complete

## 🎉 Congratulations!

You've successfully installed VinylVault! The app should now be running on your iPhone.

## 🔧 Troubleshooting Common Issues

### Issue 1: "No matching provisioning profiles found"
- **Solution**: Make sure you selected your **Personal Team** in Step 8
- Also try: Xcode → Product → Clean Build Folder, then try again

### Issue 2: iPhone doesn't appear in Xcode device list
- **Check**: Is your iPhone unlocked?
- **Check**: Did you tap "Trust" on your iPhone?
- **Try**: Disconnect and reconnect the USB cable
- **Try**: Restart both your iPhone and MacBook

### Issue 3: "Failed to register bundle identifier"
- **Solution**: In Xcode, go to Signing & Capabilities
- Change the **Bundle Identifier** to something unique
- Example: `com.yourname.VinylVault` (replace "yourname" with your name)

### Issue 4: App crashes immediately after opening
- **Solution**: On your iPhone, go to Settings → Privacy & Security
- Scroll down and make sure **Developer Mode** is enabled
- If you don't see Developer Mode, you need to enable it:
  1. Connect iPhone to Mac
  2. Open Xcode
  3. Go to Window → Devices and Simulators
  4. Select your iPhone
  5. Check "Show as run destination"
  6. Restart your iPhone

### Issue 5: "Could not launch application"
- **Solution**: On your iPhone, delete the app if it exists
- In Xcode: Product → Clean Build Folder
- Try building again from Step 9

## 📱 Using the App

### First Time Setup:
1. The app will ask for **Camera Access** - tap **Allow**
   - This is needed for barcode scanning
2. The app needs **Internet Access** - make sure you're connected to Wi-Fi or cellular

### Basic Features:
- **Home Tab**: Shows a random album from your collection each day
- **Collection Tab**: View all your vinyl records
- **Search Tab**: Search your collection
- **Lists Tab**: Create custom lists (Favorites, Wishlist, etc.)
- **+ Button**: Add new records (scan barcode or search manually)

### Adding Your First Record:
1. Tap the **+** button (floating blue button)
2. Choose **"Scan Barcode"**
3. Point your camera at a vinyl record's barcode
4. Or choose **"Search Manually"** and type the artist and album name

## 🔄 Updating the App

When new features are added, you can update the app:

1. Download the latest ZIP from GitHub again
2. Replace the old folder with the new one
3. Open the project in Xcode
4. Build and run (▶) - it will update automatically

## 📞 Getting Help

If you're stuck, you can:

1. **Take screenshots** of any error messages
2. **Check this guide** again for the specific step
3. **Ask for help** from the person who shared this app with you

## ⚠️ Important Notes

- **7-Day Limit**: Apps installed this way expire after 7 days
- **To renew**: Just build and run (▶) from Xcode again before it expires
- **Data Safety**: Your collection data is stored only on your iPhone
- **No App Store**: This is a development build, not an App Store version
- **Free Account Limit**: You can only have 3 apps installed this way at once

## 🎯 Quick Reference

| Step | What to Do | Where to Do It |
|------|------------|----------------|
| 1 | Check macOS version | Apple menu → About This Mac |
| 2 | Install Xcode | Mac App Store |
| 3 | Create Apple Developer account | Xcode → Settings → Accounts |
| 4 | Download source code | GitHub → Download ZIP |
| 5 | Connect iPhone | USB cable, tap "Trust" |
| 6 | Open project | Xcode → File → Open |
| 7 | Select device | Xcode top bar → Your iPhone |
| 8 | Set up signing | Xcode → Signing & Capabilities |
| 9 | Build and run | Click Play button (▶) |
| 10 | Trust on iPhone | Settings → General → VPN & Device Management |

## 💡 Tips for Success

1. **Be patient** - The first build takes longest
2. **Follow steps in order** - Don't skip ahead
3. **Read error messages** - They often tell you what's wrong
4. **Restart if stuck** - Sometimes restarting Xcode or your devices helps
5. **Keep iPhone connected** - During the entire installation process

---

**Enjoy managing your vinyl collection with VinylVault!** 🎵

If everything worked, you should see the app on your iPhone's home screen with a vinyl record icon. Tap it to start adding your collection!

*Last updated: March 2026*
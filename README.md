# Twin Lakes "IT Help" menu (Hello-IT fork)

Configured fork of [ygini/Hello-IT](https://github.com/ygini/Hello-IT) (BSD 3-Clause, see `LICENSE` and `NOTICE`).
It ships a menu-bar item on every Twin Lakes managed Mac with Internet state and network name, local IP,
hostname, and a Support submenu. No new Objective-C: upstream plugins plus two shell scripts.

- Plan and decisions: `Docs/twinlakes-fork-plan.md`
- Fleet scripts, profile, and installer scripts: `deploy/`
- Build and package: `package/BuildAndPackage.command`
- Branch `tlt/main` tracks upstream `develop`; the `upstream` remote is kept for cherry-picks.

Upstream README follows.

---

# Hello-IT

Hello-IT is a simple menu for the menu bar fully configurable by the IT department to provide a self-service menu. Each item of the menu can:
* display a state of service
* display a local information
* run a command
* open an app or a resource 

![Application Screenshot](/Docs/screenshot.png?raw=true "Hello IT")

You can find Hello IT release and preview version at [on the github release page](https://github.com/ygini/Hello-IT/releases)

You will learn all needed informations on the [Wiki](https://github.com/ygini/Hello-IT/wiki)

Also, note that you will find an AutoPkg recipe to keep Hello-IT up to date on [Yoann's recipes repo](https://github.com/autopkg/ygini-recipes)

# Hospital Scenario — Active Directory Build Notes

Documentation for the tiered OU structure, delegation, and GPO work built inside the CyberSafe home lab's domain (`cybersafe.local`, hosted on DC01). This models how a hospital network's AD would realistically be organized, with HIPAA-driven decisions (shared workstation lockout, least-privilege delegation) baked into the design rather than a generic corporate layout.

## Domain / environment

- Domain: `cybersafe.local`
- Domain controller: DC01 (Windows Server)
- Tools used: Active Directory Users and Computers (ADUC) and Group Policy Management (GPMC), GUI only
- Starting point: default AD install with only the built-in containers (Builtin, Computers, Domain Controllers, ForeignSecurityPrincipals, Managed Service Accounts, Users) and one domain-joined client, WIN11-CLIENT

![Default ADUC state before any custom OUs](images/4c284949-image.png)

## 1. Built the OU tree

- Created a top-level OU, **Hospital Scenario**, directly under `cybersafe.local` — kept as its own container so it doesn't collide with the lab's other generic Tier0/Tier1/Tier2 OUs.

![Hospital Scenario OU created](images/a4224674-image.png)

- Inside Hospital Scenario, created four sub-OUs representing AD's standard tiering model (based on blast radius/risk, not org chart):
  - `Tier-0` — highest-privilege tier (domain controllers, top admins)
  - `Tier-1-Servers` — application/server admins
  - `Tier-2-Clinical` — regular clinical staff (lowest-risk tier)
  - `Tier-2-Administrative` — regular admin staff (same risk tier as Clinical, different department)

![Tier-0/1/2 structure under Hospital Scenario](images/9e7687f5-image.png)

- **Why two OUs at Tier 2 instead of a Tier 3:** tiering is a privilege/blast-radius level, not a department count. Clinical and Administrative staff are both regular end users with no elevated domain rights — they're split for organization, not because one is riskier than the other. The model intentionally has no Tier 3; Tier 2 is the floor, so a compromised end-user account never has a path up to Tier 0 or Tier 1.

- Built out department/system sub-OUs inside each tier:
  - `Tier-1-Servers` → EHR-Servers, Pharmacy-Servers, Radiology-Servers
  - `Tier-2-Clinical` → Emergency, Nursing, Surgery, Radiology
  - `Tier-2-Administrative` → Billing, HR, IT

- Added test user accounts into key OUs (e.g., Ashley Moore in Emergency) so the tree wasn't empty for documentation screenshots.

![Full OU tree with all sub-OUs built out](images/42b313ea-image.png)

![Creating the Ashley AM. Moore test account in Tier-2-Clinical/Emergency](images/4f0469fc-image.png)

## 2. GPO — Nursing auto-lock policy

- Goal: shared clinical workstations (like nursing stations, used by multiple staff) are a real HIPAA exposure point, so enforced a short forced screen-lock timeout.
- Created and linked a GPO, **Nursing-AutoLock**, directly on the `Nursing` OU.
- Configured under **User Configuration → Policies → Administrative Templates → Control Panel → Personalization**:
  - Enable screen saver → Enabled
  - Password protect the screen saver → Enabled
  - Screen saver timeout → Enabled, set to 120 seconds (2 minutes)
- Used User Configuration (not Computer Configuration) so the policy follows the *user account*, not a specific machine — meaning it applies wherever that Nursing-OU user logs in, without needing a dedicated "nursing station" computer object.
- **Tested it live:** logged into WIN11-CLIENT as a Nursing test account, ran `gpupdate /force`, left it idle for 2 minutes, confirmed the machine locked and required a password to resume.

## 3. Delegation — least privilege by department

Rather than handing out Domain Admin, delegated only the specific rights each department actually needs (Delegation of Control Wizard in ADUC, right-click OU → Delegate Control).

- **IT OU** → delegated to Tina TR. Randy: "Reset user passwords and force password change at next logon." Reflects the real job — helpdesk can reset a locked-out user's password without having any broader account or domain rights.

![IT OU Advanced Security Settings confirming Tina TR. Randy has "Reset password" on descendant User objects](images/1dd6a691-image.png)

- **HR OU** → delegated to John JS. Shaw: "Create, delete, and manage user accounts." Reflects HR's real role — provisioning a new hire's account or disabling one when someone leaves — kept separate from IT's technical/security-related permissions.

![Delegation of Control Wizard — "Create, delete, and manage user accounts" selected for the HR OU](images/89ed26b5-image.png)

![HR OU test user account](images/a49eee2c-image.png)

![HR OU Advanced Security Settings showing the delegated permissions (Create/delete User objects + full control scoped to descendant User objects only)](images/ce6e3f89-image.png)

- Verified both delegations by enabling **View → Advanced Features** in ADUC, then checking each OU's Properties → Security → Advanced tab to confirm the exact permission entries — not just that the wizard "said" it worked.

## Key takeaways (for interviews / write-up)

- Tiering models privilege/blast-radius, not organizational structure — Tier 2 splits by department because HIPAA's "minimum necessary access" principle means clinical and administrative staff still shouldn't share broader access, even though neither is elevated.
- The Nursing auto-lock GPO is a direct, demonstrable control tied to a real compliance requirement, not just a generic hardening setting.
- Delegation was scoped per department's actual job function (IT = password resets, HR = account lifecycle) instead of granting broad admin rights — a concrete example of least privilege in practice.

## Planned next steps

- Isolate simulated medical devices (infusion pumps, imaging equipment) into their own OU/VLAN rather than applying the standard patching baseline, since these often run unpatchable/embedded OSes.
- Role-based security groups mapped to clinical job function (e.g., `RN-Access`, `MD-Access`, `Billing-Access`).
- A documented "break-glass" emergency access account with heavy audit logging for emergency-override scenarios.

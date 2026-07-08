# Configuring User Directories (LDAP/AD)

Jira, Confluence, and Bitbucket each authenticate against the same AD domain
controller (`devtools-labs/terraform/modules/domain-controller`) instead of
maintaining their own local user bases. Each app's embedded Crowd/user-directory
screen is configured independently in its own admin UI (there's no shared
config file or Helm value for this — it's a one-time manual setup per app),
but they all point at the same AD and hit the same gotchas.

---

## Connection Settings

| Field | Value | Why |
|---|---|---|
| Directory Type | Microsoft Active Directory | |
| Hostname | the domain controller's current private IP (`aws ec2 describe-instances` on the `WIN-SRV-01` instance, or the `/devtools/domain-controller/ldap-connection-url` SSM parameter) | see callout below — do **not** use the domain DNS name here |
| Port | `389` | Plain LDAP, not LDAPS — the domain controller isn't configured for TLS on the LDAP port |
| Use SSL | **No** | matches the plain `ldap://` scheme above |
| Username | the bind account's UPN, `<bind-username>@devtools.local` (username from `/devtools/domain-controller/ldap-bind-username`) | same bind account RHBK's `set-ldap-credentials-job.yaml` uses |
| Password | fetch with `aws ssm get-parameter --name /devtools/domain-controller/ldap-bind-password --with-decryption` | never commit this value anywhere |
| Base DN | `OU=devops-tashtiot,DC=devtools,DC=local` | from `domain-controller`'s `ou_name`/`domain_name` variables |

> **Hostname must be an IP, not `devtools.local`:** there is no DNS zone for
> the AD domain configured anywhere in this platform (no CoreDNS stub domain,
> no `hostAliases`, no Route53 private hosted zone). This matters more than it
> looks like it should — see the Follow Referrals section below.

---

## Schema Mapping

These map Active Directory's actual attribute names onto Jira/Confluence/Bitbucket's generic directory-schema fields. They're standard AD attributes, not specific to this environment, but worth having in one place since the field names in Atlassian's UI don't always make the AD equivalent obvious.

**User schema:**

| Field | Value |
|---|---|
| User Object Class | `user` |
| User Object Filter | `(&(objectCategory=Person)(sAMAccountName=*))` |
| User Name Attribute | `sAMAccountName` |
| User Name RDN Attribute | `cn` |
| User First Name Attribute | `givenName` |
| User Last Name Attribute | `sn` |
| User Display Name Attribute | `displayName` |
| User Email Attribute | `mail` |
| User Unique ID Attribute | `objectGUID` |

**Group schema:**

| Field | Value |
|---|---|
| Group Object Class | `group` |
| Group Object Filter | `(objectCategory=Group)` |
| Group Name Attribute | `cn` |
| Group Description Attribute | `description` |

**Membership schema:**

| Field | Value |
|---|---|
| Group Members Attribute | `member` |
| Use the User Membership Attribute | **"When finding the members of a group"** |

The last one is a deliberate choice, not the Atlassian default: AD's group object carries a `member` attribute listing every member's DN directly, which is the more reliable direction to resolve membership from in a flat (non-nested) group structure. `clusters-provision/clusters/rhbk`'s Keycloak LDAP federation resolves AD group membership the same way (via the group's `member` attribute, `LOAD_GROUPS_BY_MEMBER_ATTRIBUTE`, not a per-user back-link) — this keeps both integrations consistent with each other.

---

## Follow Referrals Must Be Disabled

This is the one setting most likely to trip you up, because everything else can be configured correctly and the directory will still fail — specifically on **"Test retrieve user."**

**Symptom:**

```
org.springframework.ldap.PartialResultException: nested exception is
javax.naming.PartialResultException [Root exception is
javax.naming.CommunicationException: devtools.local:389 [Root exception is
java.net.UnknownHostException: devtools.local]]
```

**Why it happens:** Active Directory frequently answers LDAP searches with a
*referral* — a response telling the client "continue this search at
`ldap://devtools.local/...`" — even when the client is already querying the
correct domain controller directly by IP. This is normal AD behavior around
naming-context boundaries and paged searches, not a sign anything is
misconfigured.

If "Follow Referrals" is enabled, Jira's (or Confluence's/Bitbucket's)
underlying LDAP client (Spring LDAP / JNDI) dutifully tries to open a *new*
connection to that referral target — which is the AD domain's DNS name
(`devtools.local`), not the IP address configured above. Since nothing in
this platform resolves that domain name (see the callout above), the
hostname lookup fails outright.

**Fix:** uncheck **"Follow Referrals"** in the directory's Advanced Settings.
There is no other side effect to turning it off here — the platform's AD
structure is flat (one OU, no nested domains/partitions), so there's nothing
a referral would ever need to point the client at anyway.

> **Why RHBK/Keycloak's LDAP federation never hit this:** Keycloak's LDAP
> provider defaults to *ignoring* referrals rather than following them, so it
> never attempts the DNS lookup that trips up Jira/Confluence/Bitbucket's
> Spring-LDAP-based clients. If a future integration exposes a referral
> setting, ignoring/not-following is the option to match this platform's
> setup.

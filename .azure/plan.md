# Plan: Align Azure OpenClaw repo for azd auto deploy

## Context
- Repository already contains `azure.yaml`, `infra/`, and `scripts/` but the README still links to the generic azd deploy buttons and does not document the automated layout Azure expects.
- User wants the repo folder structure to follow common azd automatic deployment expectations and wants the “Deploy to Azure” button to open the quick deploy experience prefilled with this repository’s template.

## Objective
1. Verify and, if required, adjust `azure.yaml`/`infra/` so that the project conforms to azd’s auto deployment layout (template metadata, parameter surface, and entry point script). 
2. Update the documentation to describe the repo structure and deployment workflow, and change the deploy button to point at a quick deploy URL that includes our repo/template address.

## Tasks
| # | Activity | Outcome | Status |
|---|----------|---------|--------|
| 1 | Inspect `azure.yaml` + `infra/` to ensure the template metadata, parameters, and script entry points match azd expectations for an automated deployment. | Confirm template reference points at `infra/main.bicep` and include any missing metadata (name, version, parameters). | completed |
| 2 | Update repository layout (if necessary) so that the AZD automation finds the expected directories (`azure.yaml`, `infra/`, `scripts/`) and that documentation clearly states this standard structure, including describing `scripts/set-openclaw.sh` as the entry helper. | Folder structure matches standard azd pattern and README summarizes it. | completed |
| 3 | Point the “Deploy to Azure” / “Deploy with azd” buttons to a quick deploy URL that encodes `https://github.com/HaoHoo/azure-opencalw` (and the relevant template path) so the portal form is prefilled with our repo. | Button opens Azure’s template deploy page with repo preselected. | completed |

## Validation Criteria
- The Azure quick deploy URL should include the encoded repo/template location and open the portal deployment form prefilled.
- README should explain the automated deployment assets and highlight the new button link.
- No manual steps should be required beyond clicking the new button and confirming the Azure form.

## Risks & Notes
- Encoding the quick deploy URL must reference a publicly accessible template (use the raw GitHub path to `azure.yaml` or `infra/main.bicep`).
- If the repo structure needs additional files for azd discovery, call that out before changing anything else.

**Next Step**: This plan has been executed and is ready for validation (e.g., run azure-validate when preparing to deploy). Let me know if you would like me to initiate validation or adjust anything further.

## Additional Objective
- Assess the environment variables referenced in `.azure/openclaw.json`, ensure every placeholder is populated by the deployment pipeline, and align `set-openclaw.sh`/Bicep so the generated `openclaw.json` matches the JSON schema (identity, commands, gateway, auth, and allowed origins).

## Tasks
| # | Activity | Outcome | Status |
|---|----------|---------|--------|
| 1 | List every `${...}` placeholder inside `.azure/openclaw.json` and trace whether Bicep exports or helper scripts already provide those env vars (including `azurePassword` and `AZURE_PUBLIC_IP`). | Confirm which env vars are already covered and which need new exports/injections. | not started |
| 2 | Update `scripts/set-openclaw.sh` so it writes the full JSON structure expected by `.azure/openclaw.json`, including `identity`, `commands`, `gateway` with `allowedOrigins`, and `auth`, drawing from the available env vars and adding `azurePassword` if necessary. | `openclaw.json` content matches the schema in the repo root, with necessary values populated from environment variables. | not started |
| 3 | Adjust `infra/resources.bicep`/`main.bicep` so the Custom Script Extension exports any missing env vars (e.g., the VM public IP and the password for the OpenClaw UI) before running `set-openclaw.sh`. | Scripts receive `AZURE_PUBLIC_IP` and `azurePassword` so the generated config can render correctly. | not started |

## Validation Criteria
- All placeholders in `.azure/openclaw.json` have corresponding env vars exported by the deployed infrastructure or helper scripts.
- The JSON written by `set-openclaw.sh` matches the schema, especially identity, commands, gateway/allowed origins, and auth sections.
- Bicep exports now include the information needed for those env vars (public IP and OpenClaw password).

## Next Step
Present this plan to the user and confirm before beginning implementation.
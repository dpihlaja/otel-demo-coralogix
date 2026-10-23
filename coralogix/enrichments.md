# Custom enrichments

Two lookup tables, uploaded from the CSVs next to this file. The collector adds the flat keys
(`transform/enrichment_keys` in `values.yaml`), because an enrichment field is a dotted path and
can't address OTel keys that contain dots.

| Table | Custom enrichment ID | Rule ID | Key field | Lands in |
|---|---|---|---|---|
| `service-catalog.csv` (team, tier, oncall, language) | 115202 | 105597 | `attributes.service_name` | `service` |
| `product-catalog.csv` (product_name, category, categories, price_usd) | 115203 | 105598 | `attributes.product_id` | `product` |

- Service catalog: `tier` is the demo's own `service.criticality`; team and on-call channel are
  illustrative ownership data, the kind a real team would keep here instead of in code.
- Product catalog: from the shop's `/api/products` (OTel demo 3.1.0), prices in USD.

To update a table, upload a new version:

```bash
curl -X PUT https://api.us2.coralogix.com/api/v1/external/custom-enrichments/115202 \
  -H "Authorization: Bearer $KEY" -F name=service-catalog -F description=... -F file=@service-catalog.csv
```

Rules: `GET/POST https://api.us2.coralogix.com/mgmt/openapi/latest/enrichment-rules/enrichment-rules/v1`
(body `{"requestEnrichments":[{"fieldName":…,"enrichedFieldName":…,"enrichmentType":{"customEnrichment":{"id":…}}}]}`).

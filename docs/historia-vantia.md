# La historia — Vantia

> Empresa **ficticia**. Cualquier parecido con una real es deliberado: el escenario está armado para
> que sea el de muchas. Esto se declara en la primera línea del README público.

## La empresa

**Vantia** es un SaaS B2B de ~60 personas. Hace un año sumó a su producto un **asistente de soporte
con IA**: el cliente escribe una consulta, el asistente busca en la base de conocimiento y en el
historial de tickets, y responde.

## La arquitectura del asistente

Tres servicios en Kubernetes, con una cola en el medio:

| Servicio | Qué hace |
|---|---|
| `vantia-gateway` | Recibe la consulta HTTP, valida el tenant, encola |
| `vantia-retrieval` | Busca en la base de conocimiento, arma el contexto |
| `vantia-llm-worker` | Llama al modelo, arma la respuesta final |
| Redis | La cola entre gateway → retrieval → worker |

Son **tres** y no cuatro a propósito: alcanzan para que una request cruce varios procesos —que es lo
que hace difícil el problema— sin inflar el lab.

**El trabajo es falso, el flujo es real.** Los servicios no llaman a un modelo de verdad: simulan la
latencia y los tokens con una distribución realista. Pero el recorrido HTTP → Redis → Redis es de
verdad, porque si el recorrido fuera falso, propagar el `request_id` sería trivial y se perdería
justamente la lección. Además, simular deja **inyectar la anomalía a propósito** y mostrar el sistema
detectándola, en vez de esperar a que ocurra.

## Los dolores, uno por fase

Cada fase cierra **un** dolor y termina con algo demostrable. Si el dolor no quedó cerrado, la fase
no está terminada, aunque los pods estén verdes.

| # | El dolor, dicho por quien lo sufre | Lo que lo cierra | Fase |
|---|---|---|---|
| 1 | *"Un cliente reclama por una respuesta que el asistente dio el martes y no podemos reconstruir qué pasó."* | Logs centralizados, correlacionados por `request_id`, con retención | **1** |
| 2 | *"Ingeniería no quiere salir de Grafana, y retener todo en OpenSearch a un año no cierra por costo."* | Loki como segundo destino del mismo pipeline; comparación con números | 2 |
| 3 | *"A veces responde en 3 segundos y a veces en 40, y no sabemos dónde se van."* | Trazas distribuidas con OTel + Tempo | 3 |
| 4 | *"La factura del modelo se triplicó y nadie sabe qué la subió."* | Tokens y costo por request como métricas, atribuibles a tenant y etapa | 4 |
| 5 | *"Tengo la alerta. ¿Y ahora dónde miro?"* | Correlación traza ↔ logs ↔ métricas, y alertas que abren en el lugar correcto | 5 |

## El hilo que atraviesa todo: el identificador de correlación

Es la espina dorsal del lab y conviene verlo desde el principio:

- **Fase 1** — el `request_id` lo genera el gateway y lo propagan los tres servicios a mano, en cada
  línea de log. Con eso ya se puede reconstruir una conversación: una búsqueda, cuatro líneas en orden.
- **Fase 3** — ese mismo identificador se convierte en un `trace_id` de OpenTelemetry, que se propaga
  solo y **se dibuja** en vez de tener que buscarse.

El post que sale de ahí no es "qué es tracing". Es *qué cambia cuando el estándar reemplaza a la
convención casera* — y es un post que se puede escribir con autoridad porque el paso anterior se hizo
a mano y se sufrió.

## Por qué dos backends de logs, y no es capricho

En Vantia conviven por **dos motivos distintos**, que es como conviven en la realidad:

- **OpenSearch** está porque el equipo de compliance exige interacciones de soporte buscables a un
  año, y el equipo de operaciones ya vive en Dashboards.
- **Loki** aparece porque ingeniería quiere ver logs sin salir de Grafana y porque el costo de
  retener todo en OpenSearch a un año no cierra.

Un pipeline, dos destinos, dos dueños. El patrón *almacén de compliance* vs *almacén de operaciones*
es real y es exactamente lo que resuelve un platform engineer.

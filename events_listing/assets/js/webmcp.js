document.addEventListener('DOMContentLoaded', async () => {
  const api = document.modelContext;
  if (!api) return;

  try {
    const events = JSON.parse(document.getElementById('webmcp-events').textContent);
    const categories = new Set(events.map(event => event.category));
    const normalize = value => value.trim().normalize('NFD').replace(/\p{M}/gu, '').toLowerCase();
    const error = (code, message) => ({ error: { code, message } });
    const invalid = message => error('invalid_arguments', message);
    const validArguments = (args, fields) => args !== null && typeof args === 'object' &&
      !Array.isArray(args) && Object.entries(args).every(([key, value]) =>
        fields.includes(key) && typeof value === 'string');
    const validDate = value => {
      if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
      const date = new Date(`${value}T00:00:00Z`);
      return !Number.isNaN(date.getTime()) && date.toISOString().slice(0, 10) === value;
    };
    const annotations = { readOnlyHint: true, untrustedContentHint: true };
    const searchFields = ['query', 'date_from', 'date_to', 'category', 'location'];

    await api.registerTool({
      name: 'search_events',
      description: 'Pesquisa eventos em curso e futuros no Porto Santo publicados no PXO Pulse. ' +
        'Combina texto, intervalo de datas, categoria e local. Não altera os filtros da página. ' +
        'query pesquisa o nome, descrição e local; location pesquisa o local; category usa o nome publicado. ' +
        'date_from e date_to são limites inclusivos no formato YYYY-MM-DD. ' +
        'Os resultados incluem identificadores para consultar os detalhes com get_event.',
      annotations,
      inputSchema: {
        type: 'object',
        properties: {
          query: { type: 'string' },
          date_from: { type: 'string' },
          date_to: { type: 'string' },
          category: { type: 'string' },
          location: { type: 'string' }
        },
        additionalProperties: false
      },
      execute: async args => {
        if (!validArguments(args, searchFields)) return invalid('Os parâmetros devem ser campos de texto válidos.');
        for (const field of ['date_from', 'date_to']) {
          if (field in args && !validDate(args[field])) return invalid('Indique datas válidas no formato YYYY-MM-DD.');
        }
        if (args.date_from && args.date_to && args.date_from > args.date_to) {
          return invalid('A data inicial não pode ser posterior à data final.');
        }
        if ('category' in args && !categories.has(args.category)) return invalid('Indique uma categoria disponível.');
        const query = normalize(args.query || '');
        const location = normalize(args.location || '');
        const matches = events.filter(event =>
          (!query || [event.name, event.description, event.location].some(text => normalize(text || '').includes(query))) &&
          (!location || normalize(event.location || '').includes(location)) &&
          (!args.category || event.category === args.category) &&
          (!args.date_from || event.end_date >= args.date_from) &&
          (!args.date_to || event.start_date <= args.date_to));
        return {
          events: matches.map(({ id, name, start_date, end_date, start_time, end_time, category, location, url }) =>
            ({ id, name, start_date, end_date, start_time, end_time, category, location, url }))
        };
      }
    });

    await api.registerTool({
      name: 'get_event',
      description: 'Consulta os detalhes públicos de um evento no Porto Santo através do identificador ' +
        'devolvido por search_events. Inclui descrição, organizador, preço, imagem e ligações publicadas.',
      annotations,
      inputSchema: {
        type: 'object',
        properties: { event_id: { type: 'string', description: 'Identificador do evento devolvido por search_events.' } },
        required: ['event_id'],
        additionalProperties: false
      },
      execute: async args => {
        if (!validArguments(args, ['event_id']) || !args.event_id?.trim()) {
          return invalid('Indique o identificador do evento.');
        }
        const event = events.find(event => event.id === args.event_id);
        return event ? { event } : error('event_not_found', 'Não foi encontrado um evento com esse identificador.');
      }
    });
  } catch (error) {
    console.error('PXO Pulse: não foi possível iniciar o WebMCP.', error);
  }
});

import type { APIRoute } from 'astro';
import { proxyApiRequest } from '../../lib/api-server';

export const prerender = false;
export const ALL: APIRoute = ({ request }) => proxyApiRequest(request);

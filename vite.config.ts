import { defineConfig } from 'vite'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = path.dirname(fileURLToPath(import.meta.url))

// Peta URL bersih → file, harus SAMA dengan PAGES di server/index.js.
// Dipakai hanya saat `npm run dev` (Vite) supaya URL bersih tidak 404.
const PAGES = {
	'/katalog': 'shop.html',
	'/produk': 'product.html',
	'/keranjang': 'checkout.html',
	'/akun': 'account.html',
	'/akun/pesanan': 'account-orders.html',
	'/akun/pesanan/lihat': 'account-order.html',
	'/admin': 'admin.html',
	'/admin/pesanan': 'admin-orders.html',
	'/admin/produk': 'admin-products.html',
}

// https://vite.dev/config/
export default defineConfig({
	server: {
		proxy: {
			'/api': 'http://localhost:8787',
		},
	},
	plugins: [
		{
			name: 'clean-urls-dev',
			configureServer(server) {
				server.middlewares.use((req, _res, next) => {
					const clean = req.url.split('?')[0]
					if (PAGES[clean]) req.url = `/${PAGES[clean]}${req.url.slice(clean.length)}`
					next()
				})
			},
		},
	],
	build: {
		rollupOptions: {
			input: {
				home: path.resolve(root, 'index.html'),
				shop: path.resolve(root, 'shop.html'),
				product: path.resolve(root, 'product.html'),
				checkout: path.resolve(root, 'checkout.html'),
				admin: path.resolve(root, 'admin.html'),
				adminOrders: path.resolve(root, 'admin-orders.html'),
				adminProducts: path.resolve(root, 'admin-products.html'),
				account: path.resolve(root, 'account.html'),
				accountOrders: path.resolve(root, 'account-orders.html'),
				accountOrder: path.resolve(root, 'account-order.html'),
			},
		},
	},
})

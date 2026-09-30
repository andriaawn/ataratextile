import { defineConfig } from 'vite'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = path.dirname(fileURLToPath(import.meta.url))

// https://vite.dev/config/
export default defineConfig({
	server: {
		proxy: {
			'/api': 'http://localhost:8787',
		},
	},
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

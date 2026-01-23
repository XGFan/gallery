import './App.css'
import Viewer from "./Viewer";
import { createBrowserRouter, RouterProvider, useLocation } from "react-router-dom";
import axios from "axios";
import { Album, customEncodeURI, generatePath, Mode, resp2Image, shuffle } from "./dto";
import RootLayout from "./layouts/RootLayout.tsx";



function ViewerWithKey() {
  const location = useLocation();
  return <Viewer key={location.pathname + location.search} />
}

const router = createBrowserRouter([
  {
    path: "*",
    element: <RootLayout>
      <ViewerWithKey />
    </RootLayout>,
    loader: async ({ request, params }) => {
      const searchParams = new URL(request.url).searchParams;
      const mode = (searchParams.get("mode") ?? "album") as Mode
      const url = customEncodeURI((params['*'] ?? ''))
      const requestMode = mode !== 'random' ? mode : 'image'
      const resp = await axios.get(`/api/${requestMode}/${url}`, {});
      const images = resp2Image(resp.data as never, requestMode);
      if (mode === 'random') {
        // shuffle images
        shuffle(images)
      }
      return {
        module: 'viewer',
        data: new Album(mode, generatePath(url), images)
      }
    }
  }
])
  ;

function App() {
  return <RouterProvider router={router} />
}

export default App

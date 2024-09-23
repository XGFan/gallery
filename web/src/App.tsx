import './App.css'
import Viewer from "./viewer.tsx";
import {createBrowserRouter, RouterProvider} from "react-router-dom";
import axios from "axios";
import {Album, customEncodeURI, generatePath, Mode, resp2Image} from "./dto.tsx";
import TitleBar from "./titlebar.tsx";
import Sidebar from "./sidebar.tsx";
import {useEffect} from "react";
import PullToRefresh from "pulltorefreshjs";


function shuffle<T>(array: T[]): T[] {
  for (let i = array.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [array[i], array[j]] = [array[j], array[i]];
  }
  return array;
}


const router = createBrowserRouter([
    {
      path: "*",
      element: <>
        <Sidebar/>
        <TitleBar/>
        <Viewer/>
      </>,
      loader: async ({request, params}) => {
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
  useEffect(() => {
    PullToRefresh.init({
      mainElement: 'body',
      onRefresh() {
        window.location.reload();
      }
    });
    return () => {
      PullToRefresh.destroyAll();
    }
  }, [])
  return (
    <RouterProvider router={router}/>
  )
}

export default App
